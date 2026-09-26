module Whatsapp::Groups
  class ParticipantDirectory
    TECHNICAL_JID = /@(lid|g\.us|broadcast)\z/i

    def initialize(group, messages)
      @group = group
      @messages = Array(messages)
      @contacts = build_contacts
    end

    def for(message)
      if message.user
        return {
          name: message.user.name,
          avatar_url: message.user.avatar_url,
          jid: nil,
          own: true
        }
      end

      if message.outgoing?
        return {
          name: I18n.t('conversations.you', default: 'Você'),
          avatar_url: '',
          jid: nil,
          own: true
        }
      end

      contact = @contacts[message.sender_jid.to_s]
      name = contact&.name.to_s.strip.presence || meaningful_sender_name(message.sender_name) || fallback_name(message)

      {
        name: name,
        avatar_url: contact&.avatar_url.to_s,
        jid: safe_jid(message.sender_jid),
        own: message.outgoing?
      }
    end

    private

    def build_contacts
      jids = @messages.filter_map { |message| message.sender_jid.to_s.presence }.uniq
      return {} if jids.empty?

      phones = {}
      identifiers = {}

      jids.each do |jid|
        if jid.match?(/\A\d+@(s\.whatsapp\.net|c\.us)\z/i)
          phones[jid] = "+#{jid.split('@', 2).first}"
        elsif jid.match?(/\A\d+@lid\z/i)
          identifiers[jid] = "whatsapp-participant:#{@group.inbox_id}:#{jid}"
        end
      end

      result = {}
      unless phones.empty?
        Contact.where(account_id: @group.account_id, phone_number: phones.values)
               .with_attached_avatar
               .find_each do |contact|
          phones.each { |jid, phone| result[jid] = contact if phone == contact.phone_number }
        end
      end

      unless identifiers.empty?
        Contact.where(account_id: @group.account_id, identifier: identifiers.values)
               .with_attached_avatar
               .find_each do |contact|
          identifiers.each { |jid, identifier| result[jid] = contact if identifier == contact.identifier }
        end
      end

      result
    end

    def meaningful_sender_name(value)
      name = value.to_s.strip
      return if name.blank? || name.match?(TECHNICAL_JID)
      return if name.match?(/\A\+?\d[\d\s().-]{7,}\z/)

      name.first(256)
    end

    def fallback_name(message)
      return I18n.t('conversations.you', default: 'Você') if message.outgoing?

      jid = message.sender_jid.to_s
      if jid.match?(/\A\d+@(s\.whatsapp\.net|c\.us)\z/i)
        return "+#{jid.split('@', 2).first}"
      end

      I18n.t('conversations.group_participant', default: 'Participante')
    end

    def safe_jid(value)
      jid = value.to_s
      return nil if jid.blank? || jid.match?(TECHNICAL_JID)

      jid
    end
  end
end
