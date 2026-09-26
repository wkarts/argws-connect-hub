module Whatsapp::Groups
  class Router
    MEDIA = %w[image audio video document sticker].freeze

    def initialize(inbox)
      @inbox = inbox
    end

    def self.declared?(value)
      value.dig(:contacts, 0, :group_id).present? || value.dig(:messages, 0, :connect_api, :remote_jid).to_s.end_with?('@g.us')
    end

    def dispatch(value, historical: false, reviewed: false)
      return yield unless self.class.declared?(value)
      message = value.dig(:messages, 0).to_h.with_indifferent_access
      context = message[:connect_api].to_h.with_indifferent_access
      jid = value.dig(:contacts, 0, :group_id).presence || context[:remote_jid]
      return unless jid.to_s.match?(WhatsappGroup::JID_PATTERN) && message[:id].present?
      return if context[:remote_jid].present? && context[:remote_jid] != jid
      existing_group = WhatsappGroup.find_by(inbox_id: @inbox.id, jid: jid)
      return unless existing_group || @inbox.channel.reload.groups_enabled?

      group = existing_group || WhatsappGroup.discover!(@inbox, jid, value.dig(:contacts, 0, :group_subject).presence || context[:group_subject])
      Lock.with(group) do
        id = message[:id].to_s
        original = group.whatsapp_group_deliveries.find_by(source_id: id)
        managed = original&.whatsapp_group_message || group.whatsapp_group_messages.find_by(source_id: id)
        if managed
          Status.apply!(managed, context[:status].to_s) if context[:status].present?
          return managed
        end
        ticket_message = original&.message || Message.where(account_id: @inbox.account_id, inbox_id: @inbox.id, source_id: id)
                                                      .where(conversation_id: group.conversations.select(:id)).first
        if ticket_message
          register!(group, ticket_message, 'conversation') unless original
          return yield # Existing-message reconciliation, not another delivery.
        end
        # Keep the ledger as a tombstone if an administrator removed the
        # underlying history. A replay must not recreate that message/ticket.
        return if original
        return unless group.active?

        timestamp = parse_time(message[:timestamp])
        if !reviewed && group.mode_changed_at && timestamp < group.mode_changed_at
          group.whatsapp_group_pending_events.find_or_create_by!(source_id: id) do |event|
            event.payload = value.deep_stringify_keys
            event.reason = 'before_mode_transition'
            event.occurred_at = timestamp
          end
          BroadcastJob.perform_later(group.id)
          return
        end

        if group.management? || reviewed
          ingest!(group, value, message, timestamp, historical || reviewed)
        else
          result = yield
          created = Message.where(account_id: @inbox.account_id, inbox_id: @inbox.id, source_id: id)
                           .where(conversation_id: group.conversations.select(:id)).first
          if created
            register!(group, created, 'conversation')
            group.update_columns(last_activity_at: [group.last_activity_at || created.created_at, created.created_at].max, updated_at: Time.current)
            BroadcastJob.perform_later(group.id, nil, nil, [], false)
          end
          result
        end
      end
    end

    def replay_pending!(group)
      raise Configuration::Conflict, 'Habilite e selecione o grupo antes de importar o histórico retido.' unless group.active?
      group.whatsapp_group_pending_events.order(:id).limit(100).each do |event|
        result = dispatch(event.payload.with_indifferent_access, historical: true, reviewed: true) { nil }
        event.destroy! if result.is_a?(WhatsappGroupMessage)
      end
    end

    private

    def ingest!(group, value, message, timestamp, historical)
      context = message[:connect_api].to_h.with_indifferent_access
      kind = message[:type].to_s
      kind = 'unsupported' unless %w[text image audio video document sticker location contacts].include?(kind)
      participant = context[:participant_alt].presence || context[:participant].presence || message[:from].presence
      sender_name = value.dig(:contacts, 0, :profile, :name).to_s.first(256)
      content = case kind
                when 'text' then message.dig(:text, :body)
                when *MEDIA then message.dig(kind, :caption)
                when 'location' then [message.dig(:location, :name), message.dig(:location, :address), message.dig(:location, :latitude), message.dig(:location, :longitude)].compact.join(' · ')
                when 'contacts' then Array(message[:contacts]).map { |contact| contact.dig(:name, :formatted_name) }.compact.join(', ')
                end
      outgoing = ActiveModel::Type::Boolean.new.cast(context[:from_me]) == true
      record = nil
      group.transaction do
        record = group.whatsapp_group_messages.create!(source_id: message[:id].to_s, direction: outgoing ? 'outgoing' : 'incoming',
          status: outgoing ? 'sent' : 'received', kind: kind, sender_jid: participant.to_s.first(128).presence,
          sender_name: sender_name.presence, content: content.to_s.first(65_536).presence,
          reply_to_source_id: message.dig(:context, :id).to_s.first(256).presence, sent_at: timestamp,
          historical: historical, policy_version: group.policy_version)
        register!(group, record, 'management')
        subject = value.dig(:contacts, 0, :group_subject).presence || context[:group_subject].presence
        updates = { last_activity_at: [group.last_activity_at || timestamp, timestamp].max }
        updates[:name] = subject.to_s.strip.first(256) if subject.present?
        group.update_columns(updates.merge(updated_at: Time.current)) # Metadata is not a policy edit.
      end
      MediaJob.perform_later(record.id) if MEDIA.include?(kind)
      Status.apply!(record, context[:status].to_s) if context[:status].present?
      record
    end

    def register!(group, message, treatment)
      attributes = { treatment: treatment, policy_version: group.policy_version }
      attributes[treatment == 'management' ? :whatsapp_group_message : :message] = message
      group.whatsapp_group_deliveries.create!(attributes.merge(source_id: message.source_id)) unless
        group.whatsapp_group_deliveries.exists?(source_id: message.source_id)
    end

    def parse_time(value)
      timestamp = Integer(value.to_s, 10)
      timestamp /= 1000 if timestamp > 10_000_000_000
      return Time.current unless timestamp.positive? && timestamp < 32_503_680_000
      Time.at(timestamp).utc
    rescue ArgumentError, RangeError
      Time.current
    end
  end
end
