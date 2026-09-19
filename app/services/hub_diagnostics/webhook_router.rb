# frozen_string_literal: true
module HubDiagnostics
  class WebhookRouter
    def self.channel_for_route(params)
      raw_phone = params[:phone_number].to_s
      digits = raw_phone.gsub(/\D/, '')
      return if digits.blank?

      Channel::Whatsapp.find_by(phone_number: raw_phone, provider: 'connectapi') ||
        Channel::Whatsapp.find_by(phone_number: "+#{digits}", provider: 'connectapi')
    end

    def self.payload_summary(params)
      data = if params.respond_to?(:to_unsafe_h)
               params.to_unsafe_h.deep_stringify_keys
             else
               params.to_h.deep_stringify_keys
             end
      entries = Array(data['entry']).select { |entry| entry.is_a?(Hash) }
      changes = entries.flat_map { |entry| Array(entry['changes']) }.select { |change| change.is_a?(Hash) }
      values = changes.filter_map { |change| change['value'] if change['value'].is_a?(Hash) }
      messages_count = values.sum { |value| Array(value['messages']).length }
      statuses_count = values.sum { |value| Array(value['statuses']).length }
      payload_kind = if messages_count.positive? && statuses_count.positive?
                       'messages_and_statuses'
                     elsif messages_count.positive?
                       'messages'
                     elsif statuses_count.positive?
                       'statuses'
                     else
                       'other'
                     end

      {
        payload_kind: payload_kind,
        entries_count: entries.length,
        changes_count: changes.length,
        messages_count: messages_count,
        statuses_count: statuses_count
      }
    rescue StandardError
      { payload_kind: 'unclassified' }
    end

    def self.enqueue(channel, params)
      config = channel.provider_config.to_h
      summary = payload_summary(params)
      expected = config['hub_binding_ref'].to_s
      provided = params[:hub_binding_ref].to_s
      pending = config['hub_pending_binding_ref'].to_s
      pending_match = pending.present? && provided.present? && ActiveSupport::SecurityUtils.secure_compare(pending, provided)

      if !pending_match && ((expected.present? && (provided.blank? || !ActiveSupport::SecurityUtils.secure_compare(expected, provided))) ||
                            (expected.blank? && provided.present?))
        Recorder.emit(
          'webhook.rejected',
          summary.merge(level: 'warn', component: 'connectapi_ingestion', channel_id: channel.id,
                        inbox_id: channel.inbox&.id, reason: 'binding_reference_mismatch')
        )
        return :forbidden
      end

      parts = EventSplitter.call(params.to_unsafe_h)
      return :unprocessable_entity if parts.empty?

      parts.each do |part|
        metadata = part.dig('entry', 0, 'changes', 0, 'value', 'metadata').to_h
        expected_phone_id = pending_match ? config['hub_pending_phone_number_id'].to_s : config['phone_number_id'].to_s
        unless metadata['phone_number_id'].to_s == expected_phone_id &&
               metadata['display_phone_number'].to_s.gsub(/\D/, '') == channel.phone_number.to_s.gsub(/\D/, '')
          Recorder.emit(
            'webhook.rejected',
            summary.merge(level: 'warn', component: 'connectapi_ingestion', channel_id: channel.id,
                          inbox_id: channel.inbox&.id, reason: 'channel_metadata_mismatch')
          )
          next
        end

        binding_id = pending_match ? config['hub_pending_binding_id'].to_s :
          (config['hub_binding_id'].to_s.presence || config['instance_name'].to_s)
        Webhooks::ConnectApiDiagnosticEventsJob.perform_later(channel.id, part, binding_id)

        value = part.dig('entry', 0, 'changes', 0, 'value')
        item = (value['messages'] || value['statuses']).first
        Recorder.emit(
          'webhook.enqueued',
          summary.merge(
            component: 'connectapi_ingestion',
            channel_id: channel.id,
            inbox_id: channel.inbox.id,
            account_id: channel.account_id,
            source_id: item['id'],
            status: item['status'],
            binding_id: binding_id
          )
        )
      end
      :ok
    rescue ArgumentError
      Recorder.emit(
        'webhook.rejected',
        payload_summary(params).merge(level: 'warn', component: 'connectapi_ingestion',
                                      channel_id: channel.id, reason: 'invalid_or_oversized_batch')
      )
      :unprocessable_entity
    end
  end
end
