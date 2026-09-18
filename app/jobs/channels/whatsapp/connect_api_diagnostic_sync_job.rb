# frozen_string_literal: true
class Channels::Whatsapp::ConnectApiDiagnosticSyncJob < Channels::Whatsapp::ConnectApiMediaSyncJob
  queue_as :high
  self.log_arguments = false
  retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 12
  def perform(channel_id, minutes, operation_id, actor_id)
    @window_minutes = [[minutes.to_i, 1].max, 120].min
    @operation_id = operation_id
    @actor_id = actor_id
    @sync_errors = 0
    @sync_queried = false
    @records_examined = 0
    HubDiagnostics::ChannelLock.with(channel_id) do
      HubDiagnostics::Recorder.emit('sync.started', operation_id: operation_id, actor_id: actor_id, channel_id: channel_id)
      super(channel_id)
      HubDiagnostics::Recorder.emit('sync.finished', operation_id: operation_id, channel_id: channel_id,
                                    count: @sync_errors, records_examined: @records_examined,
                                    result: !@sync_queried ? 'not_started' : (@sync_errors.positive? ? 'partial_failure' : 'window_processed'))
    end
  rescue StandardError => error
    HubDiagnostics::Recorder.error('sync.failed', error, operation_id: operation_id, channel_id: channel_id)
    raise
  end
  private
  def recent_native_messages
    @sync_queried = true
    records = []
    5.times do |page|
      result = client.request(:post, "/chat/findMessages/#{CGI.escape(instance_name)}", body: { page: page + 1, offset: 100 })
      batch = extract_records(result)
      records.concat(batch)
      @records_examined += batch.length
      HubDiagnostics::Recorder.emit('sync.page', operation_id: @operation_id, channel_id: @channel.id,
                                    page: page + 1, count: batch.length, has_more: batch.length == 100)
      break if batch.length < 100
    end
    if records.length >= 500
      HubDiagnostics::Recorder.emit('sync.window_capped', level: 'warn', operation_id: @operation_id,
                                    channel_id: @channel.id, count: records.length, truncated: true)
    end
    records.select do |record|
      data = record.to_h.deep_stringify_keys
      raw = data['message'].to_h
      next false if (raw.keys & %w[ephemeralMessage viewOnceMessage viewOnceMessageV2 viewOnceMessageV2Extension]).any?
      stamp = timestamp_for(record)
      stamp >= @window_minutes.minutes.ago.to_i && stamp <= 5.minutes.from_now.to_i
    end
  rescue ConnectApi::Error => error
    @sync_errors += 1
    HubDiagnostics::Recorder.error('sync.read_failed', error, operation_id: @operation_id, channel_id: @channel.id, http_status: error.status)
    raise
  end
  def sync_record(raw_record)
    record = raw_record.to_h.deep_stringify_keys
    key = record['key'].to_h.deep_stringify_keys
    id = key['id'].to_s
    return if id.blank? || ignored_jid?(key['remoteJid'])
    text = record.dig('message', 'conversation').presence || record.dig('message', 'extendedTextMessage', 'text').presence
    return super unless text.present?
    return if Message.exists?(account_id: @channel.account_id, inbox_id: @channel.inbox.id, source_id: id)
    peer = canonical_peer_phone(key)
    unless peer.present?
      HubDiagnostics::Recorder.emit('sync.skipped', level: 'warn', channel_id: @channel.id, source_id: id,
                                    operation_id: @operation_id, reason: 'peer_phone_unresolved')
      return
    end
    own = @channel.phone_number.to_s.gsub(/D/, '')
    from_me = ActiveModel::Type::Boolean.new.cast(key['fromMe'])
    payload = synthetic_webhook(record, key, id, peer, from_me, 'text', {})
    value = payload[:entry].first[:changes].first[:value]
    value[:metadata][:display_phone_number] = own
    value[:metadata][:phone_number_id] = @channel.provider_config['phone_number_id']
    value[:messages].first[:text] = { body: text.to_s }
    Whatsapp::IncomingMessageConnectApiReliableService.new(inbox: @channel.inbox, params: payload.with_indifferent_access).perform
    HubDiagnostics::Recorder.emit('sync.text_processed', channel_id: @channel.id, source_id: id,
                                  operation_id: @operation_id, from_me: from_me)
  rescue StandardError => error
    @sync_errors += 1
    HubDiagnostics::Recorder.error('sync.record_failed', error, operation_id: @operation_id, channel_id: @channel.id, source_id: id)
    raise
  end
  def timestamp_for(record)
    raw = record.to_h.deep_stringify_keys['messageTimestamp']
    value = raw.is_a?(Hash) ? raw.to_h['low'].to_i : raw.to_i
    value /= 1000 if value > 10_000_000_000
    value
  end
end
