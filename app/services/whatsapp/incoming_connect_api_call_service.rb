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
  ANSWERED_STATES = %w[ACCEPT_RECEIVED ACCEPTED CONNECTED ACTIVE IN_CALL].freeze
  RINGING_STATES = %w[CALLING RINGING OFFER_RECEIVED PRE_ACCEPT_RECEIVED INCOMING].freeze
  ENDED_STATES = %w[ENDED TERMINATED CLOSED DISCONNECTED CANCELLED CANCELED].freeze
  REJECTED_REASONS = %w[REJECTED DECLINED USER_BUSY BUSY].freeze
  NO_ANSWER_REASONS = %w[
    TIMEOUT TIMED_OUT NO_ANSWER NO_ANSWERED NOT_ANSWERED UNANSWERED
    NO_RESPONSE MISSED CALL_MISSED CALL_TIMEOUT RINGING_TIMEOUT
  ].freeze
  ANSWERED_ELSEWHERE_REASONS = %w[
    ANSWERED_ELSEWHERE ANSWERED_ON_OTHER_DEVICE ACCEPTED_ON_OTHER_DEVICE ACCEPTED_BY_OTHER_DEVICE
  ].freeze

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

    previous_snapshot = existing&.content_attributes.to_h.deep_stringify_keys&.fetch('connect_api_call', {}) || {}
    snapshot = enrich_contact_snapshot(build_snapshot(data, call, previous_snapshot), conversation)
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

  def build_snapshot(data, call, previous_snapshot = {})
    status = canonical_status(data[:action], call, previous_snapshot)
    terminal = TERMINAL_STATUSES.include?(status) || ActiveModel::Type::Boolean.new.cast(call[:terminal])

    {
      'call_id' => call[:callId].to_s,
      'action' => data[:action].to_s,
      'provider' => data[:provider].to_s,
      'direction' => normalized_direction(call),
      'status' => status,
      'terminal' => terminal,
      'provider_state' => (call[:providerState].presence || call.dig(:stateData, :state).presence || call[:state].presence).to_s,
      'provider_reason' => (call[:providerReason].presence || call.dig(:stateData, :reason).presence || call.dig(:stateData, :endReason).presence).to_s,
      'is_video' => ActiveModel::Type::Boolean.new.cast(call[:isVideo]),
      'muted' => ActiveModel::Type::Boolean.new.cast(call[:muted]),
      'peer_phone' => peer_phone(call),
      'peer_name' => call_display_name(call),
      'created_at' => call[:createdAt],
      'updated_at' => call[:updatedAt],
      'started_at' => call_timestamp(call, :startedAt, :started_at, :startTime, :start_time, :createdAt, :created_at),
      'answered_at' => call_timestamp(call, :answeredAt, :answered_at, :acceptedAt, :accepted_at, :connectedAt, :connected_at),
      'ended_at' => terminal ? call_timestamp(call, :endedAt, :ended_at, :endTime, :end_time, :updatedAt, :updated_at) : nil,
      'duration_seconds' => call_duration_seconds(call),
      'received_at' => normalize_timestamp(@params[:date_time].presence || Time.current.utc.iso8601)
    }.compact
  end

  def enrich_contact_snapshot(snapshot, conversation)
    contact = conversation.contact
    return snapshot if contact.blank?

    enriched = snapshot.deep_stringify_keys
    enriched['contact_id'] = contact.id
    enriched['peer_name'] = contact.name.to_s.strip.presence || enriched['peer_name']

    contact_phone = contact.phone_number.to_s.gsub(/\D/, '')
    enriched['peer_phone'] = contact_phone if contact_phone.present?

    thumbnail = contact.avatar_url.to_s.presence
    enriched['peer_thumbnail'] = thumbnail if thumbnail.present?
    enriched
  end

  def canonical_status(action, call, previous_snapshot = {})
    explicit = normalize_status_token(call[:status])
    return explicit if STATUS_RANK.key?(explicit) && explicit != 'unknown'

    state = normalize_status_token(call[:providerState].presence || call.dig(:stateData, :state).presence || call[:state]).upcase
    reason = normalize_status_token(call[:providerReason].presence || call.dig(:stateData, :reason).presence || call.dig(:stateData, :endReason)).upcase
    direction = normalized_direction(call)
    terminal = ActiveModel::Type::Boolean.new.cast(call[:terminal])
    previous_status = previous_snapshot.to_h.deep_stringify_keys['status'].to_s

    return 'answered_elsewhere' if ANSWERED_ELSEWHERE_REASONS.include?(reason)
    return 'failed' if action.to_s.casecmp('error').zero? || state == 'FAILED' || explicit == 'failed'
    return 'rejected' if state == 'REJECTED' || REJECTED_REASONS.include?(reason) || %w[rejected declined busy].include?(explicit)
    return no_answer_status(direction) if no_answer_marker?(reason) || no_answer_marker?(explicit.upcase)
    return 'answered' if ANSWERED_STATES.include?(state) || %w[answered accepted connected active].include?(explicit)
    return 'ringing' if action.to_s.casecmp('incoming').zero? || RINGING_STATES.include?(state) || %w[ringing calling incoming offered].include?(explicit)

    if terminal || action.to_s.casecmp('ended').zero? || ENDED_STATES.include?(state)
      return 'ended' if previous_status == 'answered' || answered_evidence?(call)

      return no_answer_status(direction)
    end

    'unknown'
  end

  def normalize_status_token(value)
    value.to_s.strip.downcase.tr(' -', '__')
  end

  def no_answer_marker?(value)
    token = value.to_s.upcase
    NO_ANSWER_REASONS.any? { |marker| token == marker || token.include?(marker) }
  end

  def no_answer_status(direction)
    direction == 'incoming' ? 'missed' : 'unanswered'
  end

  def answered_evidence?(call)
    return true if call_timestamp(call, :answeredAt, :answered_at, :acceptedAt, :accepted_at, :connectedAt, :connected_at).present?

    duration = call_duration_seconds(call)
    duration.present? && duration.positive?
  end

  def normalized_direction(call)
    direction = call[:direction].to_s.downcase
    return direction if %w[incoming outgoing].include?(direction)

    'unknown'
  end

  def call_display_name(call)
    [call[:name], call[:pushName], call[:callerPushName], call[:peerName]].map { |value| value.to_s.strip.presence }.compact.first
  end

  def call_timestamp(call, *keys)
    value = keys.lazy.map { |key| call[key] }.find(&:present?)
    normalize_timestamp(value)
  end

  def normalize_timestamp(value)
    return if value.blank?

    numeric = Float(value, exception: false)
    if numeric
      seconds = numeric > 100_000_000_000 ? numeric / 1000.0 : numeric
      return Time.at(seconds).utc.iso8601(3)
    end

    parsed = Time.zone.parse(value.to_s)
    parsed&.utc&.iso8601(3)
  rescue ArgumentError, RangeError
    nil
  end

  def call_duration_seconds(call)
    milliseconds = Float(call[:durationMs].presence || call[:duration_ms], exception: false)
    return (milliseconds / 1000.0).round if milliseconds && milliseconds >= 0

    seconds = Float(call[:durationSeconds].presence || call[:duration_seconds].presence || call[:duration], exception: false)
    return seconds.round if seconds && seconds >= 0

    nil
  end

  def enrich_timing(snapshot)
    enriched = snapshot.deep_stringify_keys
    status = enriched['status'].to_s
    terminal = ActiveModel::Type::Boolean.new.cast(enriched['terminal']) || TERMINAL_STATUSES.include?(status)

    enriched['started_at'] ||= normalize_timestamp(enriched['created_at']) || enriched['received_at']
    if status == 'answered' && enriched['answered_at'].blank?
      enriched['answered_at'] = normalize_timestamp(enriched['updated_at']) || enriched['received_at']
    end
    if terminal && enriched['ended_at'].blank?
      enriched['ended_at'] = normalize_timestamp(enriched['updated_at']) || enriched['received_at']
    end

    if enriched['duration_seconds'].blank? && enriched['answered_at'].present? && enriched['ended_at'].present?
      answered_at = parse_timestamp(enriched['answered_at'])
      ended_at = parse_timestamp(enriched['ended_at'])
      if answered_at && ended_at && ended_at >= answered_at
        enriched['duration_seconds'] = (ended_at - answered_at).round
      end
    end

    enriched.compact
  end

  def parse_timestamp(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def upsert_timeline_message(conversation, existing, snapshot)
    if existing.present?
      current = existing.content_attributes.to_h.deep_stringify_keys.fetch('connect_api_call', {})
      return existing if stale_snapshot?(current, snapshot)

      merged_snapshot = enrich_timing(current.merge(snapshot))
      return existing unless snapshot_changed?(current, merged_snapshot)

      existing.update!(
        content: timeline_content(merged_snapshot),
        content_attributes: existing.content_attributes.to_h.deep_stringify_keys.merge('connect_api_call' => merged_snapshot)
      )
      return existing
    end

    enriched_snapshot = enrich_timing(snapshot)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      status: :sent,
      source_id: source_id(enriched_snapshot['call_id']),
      content: timeline_content(enriched_snapshot),
      content_attributes: { 'connect_api_call' => enriched_snapshot }
    )
  rescue ActiveRecord::RecordNotUnique
    retry_message = timeline_message(snapshot['call_id'])
    return unless retry_message

    upsert_timeline_message(conversation, retry_message, snapshot)
  end

  def snapshot_changed?(current, incoming)
    comparable_snapshot(current) != comparable_snapshot(incoming)
  end

  def comparable_snapshot(snapshot)
    snapshot.deep_stringify_keys.except('received_at')
  end

  def stale_snapshot?(current, incoming)
    current_status = current['status'].to_s
    incoming_status = incoming['status'].to_s
    current_rank = STATUS_RANK.fetch(current_status, 0)
    incoming_rank = STATUS_RANK.fetch(incoming_status, 0)

    if ActiveModel::Type::Boolean.new.cast(current['terminal']) && current_status != 'unknown'
      return true if incoming_status != current_status
    end

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
