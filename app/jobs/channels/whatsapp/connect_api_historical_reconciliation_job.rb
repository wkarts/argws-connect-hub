# frozen_string_literal: true

require 'cgi'

class Channels::Whatsapp::ConnectApiHistoricalReconciliationJob < ApplicationJob
  queue_as :low
  self.log_arguments = false

  PAGE_SIZE = 100
  DEFAULT_MAX_PAGES = 10_000

  retry_on ConnectApi::Error, wait: 15.seconds, attempts: 8
  retry_on HubDiagnostics::BindingBusy, wait: 10.seconds, attempts: 12

  def perform(channel_id, mode:, operation_id:, actor_id:, from_at: nil, to_at: nil, page: 1)
    @operation_id = operation_id.to_s
    channel = Channel::Whatsapp.find_by(id: channel_id, provider: 'connectapi')
    return unless channel&.inbox

    HubDiagnostics::InstanceLock.with("historical-reconciliation:#{channel.id}") do
      operation = current_operation(channel)
      return unless operation['operation_id'].to_s == @operation_id

      page = page.to_i.clamp(1, max_pages)
      if operation['page'].to_i >= page
        enqueue_next_if_needed(channel, operation, mode, actor_id, from_at, to_at)
        return
      end

      mark_started(channel, operation) if page == 1 && operation['state'] == 'queued'
      response = fetch_page(channel, page, mode, from_at, to_at)
      records = extract_records(response)
      counters = counters_from(current_operation(channel))

      service = Whatsapp::ConnectApiHistoricalReconciliationService.new(
        channel: channel,
        client: client_for(channel),
        operation_id: @operation_id
      )

      records.sort_by { |record| timestamp_value(record) }.each do |record|
        counters[:examined] += 1
        result = service.process(record)
        case result.result
        when 'created' then counters[:created] += 1
        when 'existing' then counters[:updated] += 1
        else counters[:skipped] += 1
        end
      rescue StandardError
        counters[:skipped] += 1
      end

      has_more = records.length == PAGE_SIZE &&
                 page < response_pages(response) &&
                 page < max_pages
      truncated = records.length == PAGE_SIZE && page >= max_pages

      update_state(
        channel,
        state: has_more ? 'running' : (truncated ? 'completed_with_limit' : 'completed'),
        started_at: current_operation(channel)['started_at'] || Time.current.utc.iso8601,
        finished_at: has_more ? nil : Time.current.utc.iso8601,
        page: page,
        next_page: has_more ? page + 1 : nil,
        records_examined: counters[:examined],
        records_created: counters[:created],
        records_updated: counters[:updated],
        records_skipped: counters[:skipped],
        truncated: truncated
      )

      HubDiagnostics::Recorder.emit(
        'reconciliation.page_completed',
        component: 'connectapi_reconciliation',
        operation_id: @operation_id,
        actor_id: actor_id,
        channel_id: channel.id,
        inbox_id: channel.inbox.id,
        page: page,
        count: records.length,
        records_examined: counters[:examined],
        records_created: counters[:created],
        records_updated: counters[:updated],
        records_skipped: counters[:skipped],
        has_more: has_more
      )

      if has_more
        self.class.perform_later(
          channel.id,
          mode: mode,
          operation_id: @operation_id,
          actor_id: actor_id,
          from_at: from_at,
          to_at: to_at,
          page: page + 1
        )
      else
        HubDiagnostics::Recorder.emit(
          'reconciliation.completed',
          component: 'connectapi_reconciliation',
          operation_id: @operation_id,
          actor_id: actor_id,
          channel_id: channel.id,
          inbox_id: channel.inbox.id,
          count: counters[:examined],
          records_created: counters[:created],
          records_updated: counters[:updated],
          records_skipped: counters[:skipped],
          truncated: truncated
        )
      end
    end
  rescue StandardError => error
    update_state(
      channel,
      state: 'failed',
      finished_at: Time.current.utc.iso8601,
      reason: error.class.name
    ) if channel

    HubDiagnostics::Recorder.error(
      'reconciliation.failed',
      error,
      component: 'connectapi_reconciliation',
      operation_id: @operation_id,
      actor_id: actor_id,
      channel_id: channel_id
    )
    raise
  end

  private

  def fetch_page(channel, page, mode, from_at, to_at)
    body = { page: page, offset: PAGE_SIZE }
    if mode.to_s == 'range'
      from_time = Time.iso8601(from_at.to_s)
      to_time = Time.iso8601(to_at.to_s)
      body[:where] = {
        messageTimestamp: {
          gte: from_time.iso8601,
          lte: to_time.iso8601
        }
      }
    end

    client_for(channel).request(
      :post,
      "/chat/findMessages/#{CGI.escape(instance_name(channel))}",
      body: body,
      timeout: 90
    )
  end

  def extract_records(response)
    data = response.to_h.deep_stringify_keys
    Array(data.dig('messages', 'records') || data['records'] || data['data'])
  end

  def response_pages(response)
    pages = response.to_h.deep_stringify_keys.dig('messages', 'pages').to_i
    pages.positive? ? pages : Float::INFINITY
  end

  def timestamp_value(record)
    value = record.to_h.deep_stringify_keys['messageTimestamp']
    numeric = value.is_a?(Hash) ? value.deep_stringify_keys['low'].to_i : value.to_i
    numeric /= 1000 if numeric > 10_000_000_000
    numeric
  end

  def current_operation(channel)
    channel.reload.provider_config.to_h['hub_reconciliation_operation'].to_h
  end

  def mark_started(channel, operation)
    update_state(
      channel,
      operation.merge(
        'state' => 'running',
        'started_at' => Time.current.utc.iso8601
      )
    )
  end

  def counters_from(operation)
    {
      examined: operation['records_examined'].to_i,
      created: operation['records_created'].to_i,
      updated: operation['records_updated'].to_i,
      skipped: operation['records_skipped'].to_i
    }
  end

  def update_state(channel, attributes)
    channel.reload
    config = channel.provider_config.to_h.deep_dup
    operation = config['hub_reconciliation_operation'].to_h
    return if operation['operation_id'].present? && operation['operation_id'].to_s != @operation_id

    config['hub_reconciliation_operation'] = operation.merge(attributes.stringify_keys).compact
    channel.update_columns(provider_config: config, updated_at: channel.updated_at)
  end

  def enqueue_next_if_needed(channel, operation, mode, actor_id, from_at, to_at)
    return unless operation['state'] == 'running'
    next_page = operation['next_page'].to_i
    return unless next_page.positive?

    self.class.perform_later(
      channel.id,
      mode: mode,
      operation_id: @operation_id,
      actor_id: actor_id,
      from_at: from_at,
      to_at: to_at,
      page: next_page
    )
  end

  def max_pages
    ENV.fetch('HUB_CONNECT_IMPORT_MAX_PAGES', DEFAULT_MAX_PAGES).to_i.clamp(1, 100_000)
  end

  def client_for(channel)
    @client ||= if channel.provider_config.to_h['connect_api_binding_mode'] == 'existing'
                  ConnectApi::BoundInstanceClient.new(api_key: channel.provider_config.to_h['api_key'], timeout: 90)
                else
                  ConnectApi::Client.new(timeout: 90)
                end
  end

  def instance_name(channel)
    channel.provider_config.to_h['instance_name'].to_s
  end
end
