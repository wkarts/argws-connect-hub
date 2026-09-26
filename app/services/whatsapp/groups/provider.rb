require 'cgi'
require 'base64'
require 'stringio'
require 'digest'

module Whatsapp::Groups
  # Reuses the configured instance client. No global HTTP settings, protocol
  # overrides, additional service, browser or changes to the Connect API.
  class Provider
    def self.binding_token(inbox)
      config = inbox.channel.provider_config.to_h
      Digest::SHA256.hexdigest([inbox.channel_id, config['instance_name'], config['hub_binding_id'], config['hub_binding_ref']].to_json)
    end

    def initialize(inbox, client: nil)
      @inbox = inbox
      config = inbox.channel.provider_config.to_h
      @instance = CGI.escape(config.fetch('instance_name'))
      @client = client || if config['connect_api_binding_mode'] == 'existing'
                            ConnectApi::BoundInstanceClient.new(api_key: config.fetch('api_key'), timeout: 20)
                          else
                            ConnectApi::Client.new(timeout: 20)
                          end
    end

    def discover!
      response = @client.request(:get, "/group/fetchAllGroups/#{@instance}?getParticipants=false")
      entries = response.is_a?(Array) ? response : response.is_a?(Hash) ? response['groups'] || response['data'] : nil
      raise ConnectApi::Error, 'A API não retornou um catálogo de grupos válido.' unless entries.is_a?(Array) && entries.size <= 5000

      entries.each do |entry|
        next unless entry.is_a?(Hash)
        jid = entry['id'].presence || entry['jid']
        next unless jid.to_s.match?(WhatsappGroup::JID_PATTERN)

        group = WhatsappGroup.discover!(@inbox, jid, entry['subject'])
        name = entry['subject'].to_s.strip.first(256)
        group.update_columns(name: name) if name.present? && name != group.name
      end
      entries.size
    end

    def profile_picture_url(group)
      response = @client.request(
        :post,
        "/chat/fetchProfilePictureUrl/#{@instance}",
        body: { number: group.jid },
        timeout: 15
      )
      data = response.respond_to?(:deep_stringify_keys) ? response.deep_stringify_keys : {}
      data['profilePictureUrl'].to_s.presence ||
        data.dig('data', 'profilePictureUrl').to_s.presence ||
        data['url'].to_s.presence
    rescue ConnectApi::Error => e
      return nil if [400, 404, 422].include?(e.status.to_i)

      raise
    end

    def send!(message)
      group = message.whatsapp_group
      payload = { number: group.jid }
      if message.files.attached?
        file = message.files.first
        payload.merge!(mediatype: { 'image' => 'image', 'video' => 'video', 'audio' => 'audio' }.fetch(message.kind, 'document'),
                       mimetype: file.content_type, fileName: file.filename.to_s, caption: message.content.to_s,
                       media: Base64.strict_encode64(file.download))
        endpoint = message.kind == 'audio' ? 'sendWhatsAppAudio' : 'sendMedia'
        payload = { number: group.jid, audio: payload[:media] } if message.kind == 'audio'
      else
        payload[:text] = message.content.to_s
        endpoint = 'sendText'
      end
      if message.reply_to_source_id.present?
        original = group.whatsapp_group_messages.find_by!(source_id: message.reply_to_source_id)
        payload[:quoted] = { key: key_for(original) }
      end
      response = @client.request(:post, "/message/#{endpoint}/#{@instance}", body: payload)
      body = response.is_a?(Hash) ? response : {}
      direct_key = body['key'].is_a?(Hash) ? body['key'] : {}
      nested = body['data'].is_a?(Hash) ? body['data'] : {}
      nested_key = nested['key'].is_a?(Hash) ? nested['key'] : {}
      id = direct_key['id'].presence || nested_key['id']
      unless id.is_a?(String) && id.length.between?(1, 256) && !id.match?(/[\s\x00-\x1f]/)
        raise ConnectApi::Error, 'A API não confirmou o identificador da mensagem; verifique antes de reenviar.'
      end

      id
    end

    def revoke!(message)
      @client.request(:delete, "/chat/deleteMessageForEveryone/#{@instance}", body: key_for(message), timeout: 20)
    end

    def fetch_media(message)
      response = @client.request(:post, "/chat/getBase64FromMediaMessage/#{@instance}", body: { message: { key: key_for(message) }, convertToMp4: false })
      response = response['data'] if response.is_a?(Hash) && response['data'].is_a?(Hash)
      raise ConnectApi::Error, 'Mídia indisponível no provedor.' unless response.is_a?(Hash)
      encoded = response['base64'].to_s.split(',').last.to_s
      raise ConnectApi::Error, 'Arquivo maior que 25 MB.' if encoded.bytesize > (WhatsappGroupMessage::MAX_FILE_BYTES * 4 / 3 + 1024)
      binary = Base64.strict_decode64(encoded.gsub(/\s+/, ''))
      raise ConnectApi::Error, 'Arquivo vazio ou maior que 25 MB.' if binary.empty? || binary.bytesize > WhatsappGroupMessage::MAX_FILE_BYTES
      filename = File.basename(response['fileName'].to_s.tr('\\', '/')).presence || "#{message.kind}-#{message.id}"
      mime = response['mimetype'].presence || response['mimeType'].presence || 'application/octet-stream'
      { io: StringIO.new(binary), filename: filename, content_type: mime, identify: true }
    end

    private

    def key_for(message)
      { id: message.source_id, remoteJid: message.whatsapp_group.jid, fromMe: message.outgoing?, participant: message.sender_jid.presence }.compact
    end
  end
end
