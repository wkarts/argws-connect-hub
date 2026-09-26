module Whatsapp::Groups
  class NativeMessage
    WRAPPERS = %w[ephemeralMessage viewOnceMessage viewOnceMessageV2 viewOnceMessageV2Extension documentWithCaptionMessage].freeze
    MEDIA = { 'imageMessage' => 'image', 'audioMessage' => 'audio', 'videoMessage' => 'video', 'documentMessage' => 'document', 'stickerMessage' => 'sticker' }.freeze
    STATUS = { 'SERVER_ACK' => 'sent', '2' => 'sent', 'DELIVERY_ACK' => 'delivered', '3' => 'delivered', 'READ' => 'read', 'PLAYED' => 'read', '4' => 'read', '5' => 'read', 'ERROR' => 'failed', '0' => 'failed', 'DELETED' => 'deleted' }.freeze

    def self.group?(record)
      record.to_h.deep_stringify_keys.dig('key', 'remoteJid').to_s.end_with?('@g.us')
    end

    def self.envelope(record)
      record = record.to_h.deep_stringify_keys
      key = record['key'].to_h
      body = record['message'].to_h
      5.times do
        wrapper = WRAPPERS.find { |name| body[name].is_a?(Hash) }
        break unless wrapper
        body = body.dig(wrapper, 'message').to_h
      end
      media = MEDIA.keys.find { |name| body[name].is_a?(Hash) }
      kind = media ? MEDIA[media] : 'text'
      context = media ? body.dig(media, 'contextInfo').to_h : body.dig('extendedTextMessage', 'contextInfo').to_h
      message = { id: key['id'].presence || record['id'], type: kind, timestamp: record['messageTimestamp'],
                  from: key['participantAlt'].presence || key['participant'],
                  connect_api: { remote_jid: key['remoteJid'], from_me: key['fromMe'], participant: key['participant'], participant_alt: key['participantAlt'],
                                 group_subject: record['groupSubject'], recovered: true, status: STATUS[record['status'].to_s] || record['status'] },
                  context: { id: context['stanzaId'] } }
      message[kind] = media ? { id: message[:id], caption: body.dig(media, 'caption') } : { body: body['conversation'].presence || body.dig('extendedTextMessage', 'text') }
      { messages: [message], contacts: [{ group_id: key['remoteJid'], group_subject: record['groupSubject'],
                                        profile: { name: record['pushName'] } }] }.with_indifferent_access
    end
  end
end
