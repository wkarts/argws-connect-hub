# frozen_string_literal: true
module HubDiagnostics
  class WebhookRouter
    def self.channel_for_route(params)
      digits = params[:phone_number].to_s.gsub(/D/, '')
      return if digits.blank?
      Channel::Whatsapp.find_by(phone_number: "+#{digits}", provider: 'connectapi')
    end
    def self.enqueue(channel, params)
      config = channel.provider_config.to_h
      expected = config['hub_binding_ref'].to_s
      provided = params[:hub_binding_ref].to_s
      # An external binding has a per-binding URL guard. The legacy flow is not loosened.
      pending = config['hub_pending_binding_ref'].to_s
      pending_match = pending.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(pending, provided)
      if !pending_match && ((expected.present? && (provided.blank? || !ActiveSupport::SecurityUtils.secure_compare(expected, provided))) || (expected.blank? && provided.present?))
        Recorder.emit('webhook.rejected', level: 'warn', channel_id: channel.id,
                      inbox_id: channel.inbox&.id, reason: 'binding_reference_mismatch')
        return :forbidden
      end
      parts = EventSplitter.call(params.to_unsafe_h)
      return :unprocessable_entity if parts.empty?
      parts.each do |part|
        metadata = part.dig('entry', 0, 'changes', 0, 'value', 'metadata').to_h
        expected_phone_id = pending_match ? config['hub_pending_phone_number_id'].to_s : config['phone_number_id'].to_s
        unless metadata['phone_number_id'].to_s == expected_phone_id &&
               metadata['display_phone_number'].to_s.gsub(/D/, '') == channel.phone_number.to_s.gsub(/D/, '')
          Recorder.emit('webhook.rejected', level: 'warn', channel_id: channel.id,
                        inbox_id: channel.inbox&.id, reason: 'channel_metadata_mismatch')
          next
        end
        binding_id = pending_match ? config['hub_pending_binding_id'].to_s : (config['hub_binding_id'].to_s.presence || config['instance_name'].to_s)
        Webhooks::ConnectApiDiagnosticEventsJob.perform_later(channel.id, part, binding_id)
        value = part.dig('entry', 0, 'changes', 0, 'value')
        item = (value['messages'] || value['statuses']).first
        Recorder.emit('webhook.enqueued', channel_id: channel.id, inbox_id: channel.inbox.id,
                      account_id: channel.account_id, source_id: item['id'],
                      status: item['status'], binding_id: binding_id)
      end
      :ok
    rescue ArgumentError
      Recorder.emit('webhook.rejected', level: 'warn', channel_id: channel.id, reason: 'invalid_or_oversized_batch')
      :unprocessable_entity
    end
  end
end
