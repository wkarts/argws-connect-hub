# frozen_string_literal: true
require 'digest'
class Whatsapp::IncomingMessageConnectApiReliableService < Whatsapp::IncomingMessageConnectApiStatusAwareService
  def perform
    events = HubDiagnostics::EventSplitter.call(params)
    if events.length > 1
      events.each { |event| self.class.new(inbox: inbox, params: event.with_indifferent_access).perform }
      return
    end
    value = processed_params
    external_outgoing = ActiveModel::Type::Boolean.new.cast(value&.dig(:messages, 0, :connect_api, :from_me))
    HubDiagnostics::ChannelLock.with(inbox.channel.id, exclusive: external_outgoing == true) do
      inbox.channel.reload
      operation = inbox.channel.provider_config.to_h['hub_binding_operation'].to_h
      raise HubDiagnostics::BindingBusy, 'Binding transition pending' if %w[binding needs_review].include?(operation['state'])
      metadata = events.first&.dig('entry', 0, 'changes', 0, 'value', 'metadata').to_h
      unless metadata['phone_number_id'].to_s == inbox.channel.provider_config.to_h['phone_number_id'].to_s
        audit('webhook.skipped', reason: 'metadata_binding_mismatch', level: 'warn')
        return
      end
      super
    end
  end
  private
  def find_message_by_source_id(source_id)
    return if source_id.blank?
    @message = Message.find_by(account_id: inbox.account_id, inbox_id: inbox.id, source_id: source_id.to_s)
  end
  def process_messages
    source_id = @processed_params.dig(:messages, 0, :id).to_s
    if source_id.blank?
      audit('message.skipped', reason: 'source_id_missing', level: 'warn')
      return
    end
    key = Digest::SHA256.digest("hub:ingest:#{inbox.id}:#{source_id}").unpack1('q>')
    ActiveRecord::Base.transaction do
      acquired = ActiveRecord::Base.connection.select_value("SELECT pg_try_advisory_xact_lock(#{key})")
      raise HubDiagnostics::BindingBusy, 'Message ingestion pending' unless acquired == true || acquired == 't'
      if find_message_by_source_id(source_id)
        audit('message.duplicate', source_id: source_id)
        return
      end
      super
      if @message&.persisted?
        config = inbox.channel.provider_config.to_h
        HubDiagnostics::Recorder.emit(
          'message.persisted',
          HubDiagnostics::Recorder.message_attributes(@message).merge(
            channel_id: inbox.channel.id,
            from_me: outgoing_message_type?,
            direction: outgoing_message_type? ? 'outbound_external' : 'inbound',
            content_type: @message.content_type,
            message_type: @message.message_type,
            instance_name: config['instance_name'],
            provider: config['connect_api_provider'],
            component: 'connectapi_ingestion'
          )
        )
      else
        audit('message.skipped', source_id: source_id, reason: 'message_not_persisted', level: 'warn')
      end
    end
  end
  def process_statuses
    status = @processed_params.dig(:statuses, 0)
    return unless status.is_a?(Hash)
    id = status[:id].to_s
    state = status[:status].to_s
    unless id.present? && HubDiagnostics::StatusPolicy::VALID.include?(state)
      audit('status.unknown', source_id: id, status: state, level: 'warn')
      return
    end
    binding = inbox.channel.provider_config.to_h['hub_binding_id'].presence || inbox.channel.provider_config.to_h['instance_name']
    audit('status.received', source_id: id, status: state, binding_id: binding,
          provider_timestamp: status[:timestamp].to_s)
    unless find_message_by_source_id(id)
      audit('status.deferred', source_id: id, status: state, binding_id: binding, level: 'warn',
            reason: 'source_id_not_yet_persisted')
      raise HubDiagnostics::SourceMessagePending, 'Source message is not yet available'
    end
    @message.with_lock do
      previous = @message.status.to_s
      decision = HubDiagnostics::StatusPolicy.decision(previous, state)
      decision = :duplicate if state == 'deleted' && @message.content_attributes.to_h['deleted']
      if decision == :apply
        update_message_with_status(@message, status)
        audit('status.applied', source_id: id, status: @message.status, previous_status: previous,
              message_id: @message.id, conversation_id: @message.conversation_id)
      else
        audit('status.ignored', source_id: id, status: state, previous_status: previous, reason: decision.to_s)
      end
    end
  end
  def download_attachment_file(payload)
    file = super
    audit(file.present? ? 'media.downloaded' : 'media.unavailable', source_id: payload[:id].to_s, level: file.present? ? 'info' : 'warn')
    file
  end
  def native_message_by_source_id(source_id)
    record = super
    return unless record
    id = record.to_h.deep_stringify_keys.dig('key', 'id').to_s
    return record if id == source_id.to_s
    audit('native_lookup.mismatch', source_id: source_id.to_s, level: 'warn')
    nil
  end
  def set_contact
    message = @processed_params.dig(:messages, 0).to_h
    context = message[:connect_api].to_h
    if @processed_params[:contacts].blank?
      peer = canonical_peer_phone(context)
      if peer.present?
        @processed_params[:contacts] = [{ wa_id: peer, profile: { name: peer } }].map(&:with_indifferent_access)
      end
    end
    super
  end
  def outgoing_message_type?
    context = @processed_params.dig(:messages, 0, :connect_api).to_h.with_indifferent_access
    return ActiveModel::Type::Boolean.new.cast(context[:from_me]) if context.key?(:from_me) && !context[:from_me].nil?
    super
  end
  def activity_message_type?
    context = @processed_params.dig(:messages, 0, :connect_api).to_h.with_indifferent_access
    return false if ActiveModel::Type::Boolean.new.cast(context[:from_me]) && canonical_peer_phone(context).present?
    super
  end
  def message_under_process?; false; end
  def cache_message_source_id_in_redis; end
  def clear_message_source_id_from_redis; end
  def native_headers
    if inbox.channel.provider_config.to_h['connect_api_binding_mode'] == 'existing'
      token = inbox.channel.provider_config.to_h['api_key'].to_s.strip
      raise 'Instance token required' if token.blank?

      return { 'apikey' => token, 'Content-Type' => 'application/json' }
    end

    super
  end

  def audit(event, attributes = {})
    HubDiagnostics::Recorder.emit(event, {
      component: 'connectapi_ingestion', account_id: inbox.account_id, inbox_id: inbox.id, channel_id: inbox.channel.id
    }.merge(attributes))
  end
end
