# frozen_string_literal: true

class Whatsapp::IncomingConnectApiCallService
  STATUS_RANK = {
    'unknown' => 0,
    'ringing' => 1,
    'answered' => 2,
    'rejected' => 3,
    'missed' => 3,
    'unanswered' => 3,
    'ended' => 3,
    'failed' => 3,
    'answered_elsewhere' => 3
  }.freeze

  TERMINAL_STATUSES = %w[rejected missed unanswered ended failed answered_elsewhere].freeze

  def initialize(channel:, params:, conversation: nil)
    @channel = channel
    @params = params.to_h.with_indifferent_access
    @conversation = conversation
  end

  def perform
    return unless @params[:event].to_s.casecmp('call').zero?

    data = @params[:data].to_h.with_indifferent_access
    call = data[:call].to_h.with_indifferent_access
    return log_ignored('missing call payload') if call.blank?

    call_id = call[:callId].to_s.strip
    return log_ignored('missing callId') if call_id.blank?

    existing = timeline_message(call_id)
    conversation = @conversation || existing&.conversation || resolve_conversation(call)
    return log_ignored("conversation not found callId=#{call_id}") if conversation.blank?

    snapshot = build_snapshot(data, call)
    upsert_timeline_message(conversation, existing, snapshot)
  end

  private

  attr_reader :channel

  def inbox
    channel.inbox
  end

  def timeline_message(call_id)
    Message.find_by(inbox_id: inbox.id, source_id: source_id(call_id))
  end

  def source_id(call_id)
    "connect-api-call:#{call_id}"
  end

  def resolve_conversation(call)
    phone = peer_phone(call)
    return if phone.blank?

    contact_inbox = find_or_create_contact_inbox(phone, call)
    return if contact_inbox.blank?

    if inbox.lock_to_single_conversation
      contact_inbox.conversations.last || create_conversation(contact_inbox)
    else
      contact_inbox.conversations.where.not(status: :resolved).last || create_conversation(contact_inbox)
    end
  end

  def find_or_create_contact_inbox(phone, call)
    normalized = normalize_brazil_number(phone)
    contact_inbox = inbox.contact_inboxes.find_by(source_id: normalized) || inbox.contact_inboxes.find_by(source_id: phone)
    return contact_inbox if contact_inbox.present?

    ContactInboxWithContactBuilder.new(
      source_id: normalized,
      inbox: inbox,
      contact_attributes: {
        phone_number: "+#{normalized}",
        name: call_display_name(call) || "+#{normalized}"
      }
    ).perform
  end

  def create_conversation(contact_inbox)
    Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def peer_phone(call)
    candidates = [
      call[:displayPeerJid],
      call[:callerPnJid],
      call[:callerPn],
      call[:peerJidAlt],
      call[:remoteJid],
      call[:peerJid]
    ]

    candidates.each do |candidate|
      value = candidate.to_s.strip
      next if value.blank? || value.end_with?('@lid')

      local = value.split('@').first.to_s.split(':').first.to_s
      digits = local.gsub(/\D/, '')
      return digits if digits.length.between?(8, 15)
    end

    nil
  end

  def normalize_brazil_number(phone)
    return phone unless phone.start_with?('55') && phone.length >= 12

    ddd = phone[2, 2]
    number = phone[4..]
    return phone unless number.present?

    normalized = "55#{ddd}#{number}"
    normalized = "55#{ddd}9#{number}" if %w[6 7 8 9].include?(number[0]) && normalized.length != 13
    normalized
  end

  def build_snapshot(data, call)
    status = canonical_status(data[:action], call)

    {
      'call_id' => call[:callId].to_s,
      'action' => data[:action].to_s,
      'provider' => data[:provider].to_s,
      'direction' => normalized_direction(call),
      'status' => status,
      'terminal' => TERMINAL_STATUSES.include?(status) || ActiveModel::Type::Boolean.new.cast(call[:terminal]),
      'provider_state' => (call[:providerState].presence || call.dig(:stateData, :state).presence || call[:state].presence).to_s,
      'provider_reason' => (call[:providerReason].presence || call.dig(:stateData, :reason).presence || call.dig(:stateData, :endReason).presence).to_s,
      'is_video' => ActiveModel::Type::Boolean.new.cast(call[:isVideo]),
      'muted' => ActiveModel::Type::Boolean.new.cast(call[:muted]),
      'peer_phone' => peer_phone(call),
      'peer_name' => call_display_name(call),
      'created_at' => call[:createdAt],
      'updated_at' => call[:updatedAt],
      'received_at' => @params[:date_time].presence || Time.current.utc.iso8601
    }.compact
  end

  def canonical_status(action, call)
    explicit = call[:status].to_s.downcase
    return explicit if STATUS_RANK.key?(explicit)

    state = (call[:providerState].presence || call.dig(:stateData, :state).presence || call[:state]).to_s.upcase
    reason = (call[:providerReason].presence || call.dig(:stateData, :reason).presence || call.dig(:stateData, :endReason)).to_s.upcase
    direction = normalized_direction(call)

    return 'answered_elsewhere' if %w[ANSWERED_ELSEWHERE ANSWERED_ON_OTHER_DEVICE ACCEPTED_ON_OTHER_DEVICE ACCEPTED_BY_OTHER_DEVICE].include?(reason)
    return 'failed' if action.to_s.casecmp('error').zero? || state == 'FAILED'
    return 'rejected' if state == 'REJECTED' || %w[REJECTED USER_BUSY].include?(reason)
    return direction == 'incoming' ? 'missed' : 'unanswered' if reason == 'TIMEOUT'
    return 'ended' if action.to_s.casecmp('ended').zero? || state == 'ENDED'
    return 'answered' if %w[ACCEPT_RECEIVED CONNECTED].include?(state)
    return 'ringing' if action.to_s.casecmp('incoming').zero? || %w[CALLING OFFER_RECEIVED PRE_ACCEPT_RECEIVED].include?(state)

    'unknown'
  end

  def normalized_direction(call)
    direction = call[:direction].to_s.downcase
    return direction if %w[incoming outgoing].include?(direction)

    'unknown'
  end

  def call_display_name(call)
    [call[:name], call[:pushName], call[:callerPushName], call[:peerName]].map { |value| value.to_s.strip.presence }.compact.first
  end

  def upsert_timeline_message(conversation, existing, snapshot)
    if existing.present?
      current = existing.content_attributes.to_h.deep_stringify_keys.fetch('connect_api_call', {})
      return if stale_snapshot?(current, snapshot)

      existing.update!(
        content: timeline_content(snapshot),
        content_attributes: existing.content_attributes.to_h.deep_stringify_keys.merge('connect_api_call' => current.merge(snapshot))
      )
      return existing
    end

    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      status: :sent,
      source_id: source_id(snapshot['call_id']),
      content: timeline_content(snapshot),
      content_attributes: { 'connect_api_call' => snapshot }
    )
  rescue ActiveRecord::RecordNotUnique
    retry_message = timeline_message(snapshot['call_id'])
    return unless retry_message

    upsert_timeline_message(conversation, retry_message, snapshot)
  end

  def stale_snapshot?(current, incoming)
    current_status = current['status'].to_s
    incoming_status = incoming['status'].to_s
    current_rank = STATUS_RANK.fetch(current_status, 0)
    incoming_rank = STATUS_RANK.fetch(incoming_status, 0)

    return true if current['terminal'] && current_status != 'unknown'

    incoming_rank < current_rank
  end

  def timeline_content(snapshot)
    status = snapshot['status']
    direction = snapshot['direction']

    label = case status
            when 'ringing'
              direction == 'incoming' ? 'Chamada recebida' : 'Chamada efetuada'
            when 'answered' then 'Chamada atendida'
            when 'rejected' then 'Chamada recusada'
            when 'missed' then 'Chamada perdida'
            when 'unanswered' then 'Chamada não atendida'
            when 'ended' then 'Chamada encerrada'
            when 'failed' then 'Falha na chamada'
            when 'answered_elsewhere' then 'Chamada atendida em outro dispositivo'
            else 'Atualização de chamada'
            end

    snapshot['is_video'] ? "#{label} · vídeo" : label
  end

  def log_ignored(reason)
    Rails.logger.debug("[HUB Connect|API Call] ignored #{reason}")
    nil
  end
end
