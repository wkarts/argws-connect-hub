# frozen_string_literal: true
require 'cgi'
require 'digest'
require 'uri'
module ConnectApi
  class ExistingInstanceBinding
    class Rejected < StandardError; end
    PROVIDERS = %w[WHATSAPP-BAILEYS WHATSAPP-ZAPO].freeze
    def initialize(channel:, instance_name:, api_key:)
      @channel = channel
      @name = instance_name.to_s.strip
      @key = api_key.to_s.strip
      raise Rejected, 'Informe o nome exato da instância.' unless @name.match?(/\A[\p{L}\p{N}_.:@ -]{1,160}\z/u)
      raise Rejected, 'Nome de instância inválido.' if %w[. ..].include?(@name)
      raise Rejected, 'Informe uma chave de API válida, sem quebras de linha.' if @key.empty? || @key.bytesize > 4096 || @key.match?(/[\r\n\x00]/)
      raise Rejected, 'A caixa deve utilizar Connect|API.' unless @channel.provider == 'connectapi' && @channel.inbox
      # The submitted key is mandatory. Never silently fall back to the installation key.
      @client = ConnectApi::BoundInstanceClient.new(api_key: @key, timeout: 4)
    end
    def self.local_fingerprint(channel)
      config = channel.provider_config.to_h
      Digest::SHA256.hexdigest(JSON.generate([
        channel.id, channel.account_id, channel.phone_number, channel.provider,
        config['instance_name'], config['api_key'], config['phone_number_id'], config['hub_binding_id']
      ]))
    end
    def preview
      assert_unclaimed!
      instances = ConnectApi::Client.new(timeout: 4).fetch_instances
      record = instances.find do |row|
        row.is_a?(Hash) && (row['name'] || row['instanceName'] || row['instanceId']).to_s == @name
      end
      raise Rejected, 'A instância não foi encontrada na Connect|API configurada.' unless record
      provider = (record['integration'] || record['provider']).to_s
      raise Rejected, 'Esta integração não é compatível com a vinculação.' unless PROVIDERS.include?(provider)
      meta = read_meta
      raise Rejected, 'Ative e valide a compatibilidade Meta desta instância antes de vinculá-la.' if meta['phoneNumberId'].blank?
      state = @client.connection_state(@name)
      phone = meta['displayPhoneNumber'].to_s.gsub(/\D/, '').presence ||
              record['number'].to_s.gsub(/\D/, '').presence || record['ownerJid'].to_s.split('@').first.to_s.gsub(/\D/, '')
      unless phone.present? && phone == @channel.phone_number.to_s.gsub(/\D/, '')
        raise Rejected, 'O número da instância deve ser o mesmo número WhatsApp da caixa. Troca de número exige uma migração separada.'
      end
      current_url = meta['webhookUrl'].to_s
      desired_base = base_webhook_url
      current_base = current_url.split('?', 2).first.sub(%r{/+$}, '')
      {
        'channel_id' => @channel.id, 'instance_name' => @name, 'phone' => phone, 'provider' => provider,
        'state' => state.is_a?(Hash) ? state.dig('instance', 'state').to_s : '',
        'webhook_display' => safe_url(current_url),
        'requires_takeover' => current_url.present? && current_base != desired_base,
        'local_fingerprint' => self.class.local_fingerprint(@channel),
        'remote_fingerprint' => remote_fingerprint(meta)
      }
    rescue ConnectApi::Error
      raise Rejected, 'A validação da instância/chave falhou. Verifique a credencial, a disponibilidade e a compatibilidade Meta da instância.'
    end
    def apply!(proof:, actor_id:, operation_id:, allow_takeover: false)
      HubDiagnostics::ChannelLock.with(@channel.id, exclusive: true) do
        @channel.reload
        operation = @channel.provider_config.to_h['hub_binding_operation'].to_h
        return if operation['operation_id'] == operation_id && operation['state'] == 'applied'
        raise Rejected, 'Existe uma recuperação pendente. Restaure o webhook anterior antes de outra troca.' if operation['state'] == 'needs_review'
        fresh = preview
        unless fresh['local_fingerprint'] == proof['local_fingerprint'] && fresh['remote_fingerprint'] == proof['remote_fingerprint']
          raise Rejected, 'O vínculo ou o webhook mudou depois da validação. Valide novamente.'
        end
        if fresh['requires_takeover'] && !allow_takeover
          raise Rejected, 'O webhook atende outro endereço. A substituição precisa de autorização explícita.'
        end
        pending = Message.where(inbox_id: @channel.inbox.id, message_type: %w[outgoing template], status: 'progress').exists?
        raise Rejected, 'Há mensagens em processamento nesta caixa. Reconcilie os status antes de trocar a instância.' if pending
        before_meta = read_meta
        old_config = @channel.provider_config.to_h.deep_dup
        binding_id = SecureRandom.uuid
        binding_ref = SecureRandom.hex(24)
        desired_url = "#{base_webhook_url}?hub_binding_ref=#{binding_ref}"
        recovery = {
          'base_url' => @client.base_url, 'instance_name' => @name, 'api_key' => @key,
          'before_meta' => before_meta.slice('enabled', 'webhookUrl'), 'desired_url' => desired_url
        }
        staged = old_config.merge(
          'hub_pending_binding_ref' => binding_ref, 'hub_pending_binding_id' => binding_id,
          'hub_pending_phone_number_id' => before_meta['phoneNumberId'].to_s,
          'hub_binding_recovery' => HubDiagnostics::SecretBox.encrypt(recovery),
          'hub_binding_operation' => { 'operation_id' => operation_id, 'state' => 'binding', 'instance_name' => @name }
        )
        persist(staged)
        begin
          @client.request(:put, meta_path, body: { enabled: true, webhookUrl: desired_url }, timeout: 10)
          after_meta = read_meta
          unless after_meta['enabled'] == true && after_meta['webhookUrl'].to_s == desired_url &&
                 after_meta['displayPhoneNumber'].to_s.gsub(/\D/, '') == fresh['phone'] && after_meta['phoneNumberId'].to_s == before_meta['phoneNumberId'].to_s
            raise Rejected, 'O webhook ou o número da instância não foi confirmado pela API.'
          end
          config = old_config.merge(
            'instance_name' => @name, 'api_key' => @key, 'connect_api_binding_mode' => 'existing',
            'hub_binding_id' => binding_id, 'hub_binding_ref' => binding_ref,
            'connect_api_provider' => fresh['provider'], 'phone_number_id' => after_meta['phoneNumberId'].to_s,
            'business_account_id' => after_meta['businessAccountId'].to_s,
            'display_phone_number' => after_meta['displayPhoneNumber'].to_s,
            'graph_url' => "#{@client.base_url}/graph", 'url' => "#{@client.base_url}/graph",
            'meta_webhook_url' => desired_url, 'meta_compatible' => true, 'meta_compatible_verified' => true,
            'meta_compatible_verified_at' => Time.current.utc.iso8601, 'communication_ready' => true,
            'connect_api_manual_deletion' => false, 'provisioned' => true,
            'calls_supported' => fresh['provider'] == 'WHATSAPP-ZAPO', 'voice_supported' => fresh['provider'] == 'WHATSAPP-ZAPO',
            'native_call_webhook_enabled' => false, 'connection_status' => fresh['state'], 'last_error' => nil,
            'hub_binding_previous_instance' => old_config['instance_name'],
            'hub_binding_operation' => { 'operation_id' => operation_id, 'state' => 'applied', 'instance_name' => @name }
          )
          %w[connect disconnect force_reconcile hub_pending_binding_ref hub_pending_binding_id hub_pending_phone_number_id hub_binding_recovery
             native_call_webhook_url native_call_webhook_verified_at native_call_webhook_last_error].each { |key| config.delete(key) }
          # Deliberately bypass the model's provisioning validation: this operation must never create/re-pair/delete sessions.
          @channel.update_columns(provider_config: config, message_templates: [], message_templates_last_updated: nil, updated_at: Time.current)
          HubDiagnostics::Recorder.emit('binding.applied', operation_id: operation_id, actor_id: actor_id,
                                        channel_id: @channel.id, inbox_id: @channel.inbox.id, instance_name: @name)
        rescue StandardError => error
          restored = restore_remote(recovery)
          reverted = old_config.merge('hub_binding_operation' => {
            'operation_id' => operation_id, 'state' => restored ? 'failed_restored' : 'needs_review', 'instance_name' => @name
          })
          reverted['hub_binding_recovery'] = staged['hub_binding_recovery'] unless restored
          persist(reverted)
          HubDiagnostics::Recorder.error('binding.failed', error, operation_id: operation_id, actor_id: actor_id,
                                         channel_id: @channel.id, reason: restored ? 'remote_restored' : 'remote_state_indeterminate')
          raise Rejected, restored ? 'A troca falhou e o webhook anterior foi restaurado.' : 'A troca não foi concluída; o estado remoto exige recuperação antes de novos envios.'
        end
      end
    end
    def recover!(actor_id:, operation_id:)
      HubDiagnostics::ChannelLock.with(@channel.id, exclusive: true) do
        @channel.reload
        config = @channel.provider_config.to_h.deep_dup
        recovery = HubDiagnostics::SecretBox.decrypt(config.fetch('hub_binding_recovery'))
        raise Rejected, 'A configuração da Connect|API mudou; recuperação automática bloqueada.' unless recovery['base_url'] == @client.base_url && recovery['instance_name'] == @name
        raise Rejected, 'O webhook foi alterado por outra operação ou a API não confirmou a restauração.' unless restore_remote(recovery)
        config.delete('hub_binding_recovery')
        config.delete('hub_pending_binding_ref')
        config.delete('hub_pending_binding_id')
        config.delete('hub_pending_phone_number_id')
        config['hub_binding_operation'] = { 'operation_id' => operation_id, 'state' => 'failed_restored', 'instance_name' => @name }
        persist(config)
        HubDiagnostics::Recorder.emit('binding.recovered', operation_id: operation_id, actor_id: actor_id, channel_id: @channel.id)
      end
    end
    private
    def restore_remote(recovery)
      current = read_meta
      before = recovery.fetch('before_meta')
      return true if remote_fingerprint(current) == remote_fingerprint(before)
      return false unless current['webhookUrl'].to_s == recovery['desired_url']
      @client.request(:put, meta_path, body: { enabled: before['enabled'] == true, webhookUrl: before['webhookUrl'] }, timeout: 10)
      remote_fingerprint(read_meta) == remote_fingerprint(before)
    rescue StandardError
      false
    end
    def persist(config)
      @channel.update_columns(provider_config: config, updated_at: Time.current)
    end
    def read_meta
      response = @client.request(:get, meta_path, timeout: 4)
      raise Rejected, 'A API não retornou uma configuração Meta válida.' unless response.is_a?(Hash)
      response.deep_stringify_keys
    end
    def meta_path
      "/compat/meta/#{CGI.escape(@name)}"
    end
    def base_webhook_url
      frontend = ENV.fetch('FRONTEND_URL', '').to_s.sub(%r{/+$}, '')
      uri = URI.parse(frontend)
      raise Rejected, 'FRONTEND_URL deve ser HTTPS, sem credenciais ou query string.' unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      "#{frontend}/webhooks/whatsapp/#{@channel.phone_number.to_s.gsub(/\D/, '')}"
    rescue URI::InvalidURIError
      raise Rejected, 'FRONTEND_URL inválida.'
    end
    def assert_unclaimed!
      duplicate = Channel::Whatsapp.where(provider: 'connectapi').where.not(id: @channel.id)
                                   .where("provider_config ->> 'instance_name' = ?", @name).exists?
      raise Rejected, 'Esta instância já está vinculada a outra caixa de entrada.' if duplicate
    end
    def remote_fingerprint(meta)
      Digest::SHA256.hexdigest(JSON.generate([meta['enabled'] == true, meta['webhookUrl'].to_s]))
    end
    def safe_url(value)
      uri = URI.parse(value)
      return '' unless uri.is_a?(URI::HTTP) && uri.host
      "#{uri.scheme}://#{uri.host}#{uri.port == uri.default_port ? '' : ":#{uri.port}"}#{uri.path}"
    rescue URI::InvalidURIError
      '[URL inválida]'
    end
  end
end
