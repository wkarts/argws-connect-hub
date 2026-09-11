# frozen_string_literal: true

class Whatsapp::ConnectApiCallTimelineSyncService
  def initialize(channel:, conversation:)
    @channel = channel
    @conversation = conversation
  end

  def sync(call, action: nil, status: nil, direction: nil, terminal: nil, peer_phone: nil, peer_name: nil)
    item = call.to_h.deep_stringify_keys
    call_id = item['callId'].presence || item['id'].presence
    return if call_id.blank?

    now = Time.current.utc.iso8601(3)
    normalized_call = item.merge(
      'callId' => call_id,
      'status' => status.presence || item['status'],
      'direction' => direction.presence || item['direction'],
      'updatedAt' => item['updatedAt'].presence || item['updated_at'].presence || now
    ).compact

    normalized_call['terminal'] = terminal unless terminal.nil?
    normalized_call['peerName'] = peer_name if peer_name.present? && normalized_call['peerName'].blank?
    attach_peer_phone!(normalized_call, peer_phone)

    Whatsapp::IncomingConnectApiCallService.new(
      channel: @channel,
      conversation: @conversation,
      params: {
        event: 'call',
        instance: instance_name,
        date_time: normalized_call['updatedAt'],
        data: {
          action: action.presence || action_for(normalized_call['status']),
          provider: provider_name,
          call: normalized_call
        }
      }
    ).perform
  end

  private

  def provider_config
    @provider_config ||= @channel.provider_config.to_h.deep_stringify_keys
  end

  def instance_name
    provider_config['instance_name'].to_s
  end

  def provider_name
    provider_config['connect_api_provider'].to_s.presence || 'WHATSAPP-ZAPO'
  end

  def attach_peer_phone!(call, value)
    digits = value.to_s.gsub(/\D/, '')
    return if digits.blank?
    return if [call['displayPeerJid'], call['callerPnJid'], call['callerPn'], call['peerJidAlt'], call['remoteJid'], call['peerJid']].any?(&:present?)

    call['displayPeerJid'] = "#{digits}@s.whatsapp.net"
    call['callerPn'] = digits
  end

  def action_for(status)
    case status.to_s.downcase
    when 'ringing' then 'state'
    when 'answered' then 'state'
    when 'rejected', 'missed', 'unanswered', 'ended', 'answered_elsewhere' then 'ended'
    when 'failed' then 'error'
    else 'state'
    end
  end
end
