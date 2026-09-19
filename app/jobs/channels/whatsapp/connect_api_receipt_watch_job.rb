# frozen_string_literal: true

require 'cgi'

class Channels::Whatsapp::ConnectApiReceiptWatchJob < ApplicationJob
  queue_as :high
  self.log_arguments = false

  CHECK_DELAYS = [2, 3, 5, 8, 12, 20, 30].freeze
  STATUS_RANK = { 'sent' => 1, 'delivered' => 2, 'read' => 3 }.freeze
  STATUS_MAP = {
    '2' => 'sent', 'SERVER_ACK' => 'sent',
    '3' => 'delivered', 'DELIVERY_ACK' => 'delivered',
    '4' => 'read', '5' => 'read', 'READ' => 'read', 'PLAYED' => 'read',
    '0' => 'failed', 'ERROR' => 'failed'
  }.freeze

  def perform(message_id, attempt = 0)
    message = Message.find_by(id: message_id)
    return unless message&.source_id.present?
    return unless message.outgoing? || message.template?

    channel = message.inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'connectapi'
    return if terminal?(message.status)

    status = fetch_best_status(channel, message.source_id)
    apply_status(message, status) if status.present?

    message.reload
    return if terminal?(message.status)

    schedule_next(message.id, attempt)
  rescue ConnectApi::Error => error
    HubDiagnostics::Recorder.emit(
      'receipt.watch_failed',
      level: 'warn',
      component: 'connectapi_receipt',
      message_id: message_id,
      attempt: attempt,
      http_status: error.status,
      reason: 'connect_api_error'
    )
    schedule_next(message_id, attempt)
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'receipt.watch_failed',
      error,
      component: 'connectapi_receipt',
      message_id: message_id,
      attempt: attempt
    )
    schedule_next(message_id, attempt)
  end

  private

  def fetch_best_status(channel, source_id)
    response = client_for(channel).request(
      :post,
      "/chat/findStatusMessage/#{CGI.escape(instance_name(channel))}",
      body: {
        where: { id: source_id },
        page: 1,
        offset: 50
      },
      timeout: 10
    )

    statuses = Array(response).filter_map do |row|
      STATUS_MAP[row.to_h.deep_stringify_keys['status'].to_s.upcase]
    end

    successes = statuses.select { |status| STATUS_RANK.key?(status) }
    best = successes.max_by { |status| STATUS_RANK[status] }
    best || (statuses.include?('failed') ? 'failed' : nil)
  end

  def apply_status(message, incoming)
    message.with_lock do
      message.reload
      decision = HubDiagnostics::StatusPolicy.decision(message.status.to_s, incoming)
      return unless decision == :apply

      previous = message.status
      message.update!(status: incoming)

      HubDiagnostics::Recorder.emit(
        'receipt.watch_applied',
        component: 'connectapi_receipt',
        account_id: message.account_id,
        inbox_id: message.inbox_id,
        conversation_id: message.conversation_id,
        message_id: message.id,
        source_id: message.source_id,
        previous_status: previous,
        status: incoming
      )
    end
  end

  def schedule_next(message_id, attempt)
    next_attempt = attempt.to_i + 1
    return if next_attempt >= CHECK_DELAYS.length

    self.class.set(wait: CHECK_DELAYS[next_attempt].seconds).perform_later(message_id, next_attempt)
  end

  def terminal?(status)
    %w[read failed].include?(status.to_s)
  end

  def client_for(channel)
    if channel.provider_config.to_h['connect_api_binding_mode'] == 'existing'
      ConnectApi::BoundInstanceClient.new(
        api_key: channel.provider_config.to_h['api_key'],
        timeout: 10
      )
    else
      ConnectApi::Client.new(timeout: 10)
    end
  end

  def instance_name(channel)
    channel.provider_config.to_h['instance_name'].to_s
  end
end
