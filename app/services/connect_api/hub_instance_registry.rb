# frozen_string_literal: true

module ConnectApi
  class HubInstanceRegistry
    CALL_PROVIDER = 'WHATSAPP-ZAPO'

    def initialize(client: ConnectApi::Client.new)
      @client = client
    end

    def overview
      root = @client.root
      instances = @client.fetch_instances
      mappings = hub_mappings
      decorated = instances.map { |instance| decorate(instance, mappings) }
      visible = decorated.select { |item| item[:hub_owned] }

      {
        online: true,
        version: root.is_a?(Hash) ? root['version'] : nil,
        manager_url: manager_url(root),
        total_instances: visible.size,
        remote_total_instances: decorated.size,
        hub_instances: visible.count { |item| item[:hub_managed] },
        connected_instances: visible.count { |item| connected?(item[:status]) },
        call_capable_instances: visible.count { |item| item[:calls_supported] },
        instances: visible.sort_by { |item| [item[:hub_managed] ? 0 : 1, item[:name].to_s.downcase] }
      }
    rescue ConnectApi::Error => e
      {
        online: false,
        error: e.message,
        version: nil,
        manager_url: configured_manager_url,
        total_instances: 0,
        remote_total_instances: 0,
        hub_instances: hub_mappings.size,
        connected_instances: 0,
        call_capable_instances: 0,
        instances: []
      }
    end

    def managed_channel(instance_name)
      mapping = hub_mappings[instance_name.to_s]
      mapping && mapping[:channel]
    end

    def hub_owned?(instance_name)
      managed_channel(instance_name).present? || ConnectApi::InstanceNamespace.owned?(instance_name)
    end

    def mark_manually_deleted!(instance_name)
      channel = managed_channel(instance_name)
      return unless channel

      config = channel.provider_config.to_h.deep_stringify_keys
      config['connect_api_manual_deletion'] = true
      config['provisioned'] = false
      config['communication_ready'] = false
      config['meta_compatible_verified'] = false
      config['connection_status'] = 'deleted'
      config['last_error'] = 'Instância removida pelo administrador. Use Reconciliar agora para recriá-la.'

      # Existing live legacy names are deliberately preserved. Once an
      # administrator explicitly deletes one of them, however, the next manual
      # reconciliation is a new provisioning event and must adopt the immutable
      # HUB namespace contract.
      unless ConnectApi::InstanceNamespace.owned?(instance_name)
        config['legacy_instance_name'] = instance_name
        config.delete('instance_name')
        config.delete('api_key')
      end

      channel.update_columns(provider_config: config, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def sync_provider!(instance_name, provider)
      channel = managed_channel(instance_name)
      return unless channel

      config = channel.provider_config.to_h.deep_stringify_keys
      config['connect_api_provider'] = provider
      config['calls_supported'] = provider == CALL_PROVIDER
      config['voice_supported'] = provider == CALL_PROVIDER
      channel.update_columns(provider_config: config, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    private

    def hub_mappings
      @hub_mappings ||= Channel::Whatsapp
                        .where(provider: 'connectapi')
                        .includes(:inbox, :account)
                        .each_with_object({}) do |channel, result|
        instance_name = channel.provider_config.to_h['instance_name'].to_s
        next if instance_name.blank?

        result[instance_name] = {
          channel: channel,
          inbox: channel.inbox,
          account: channel.account
        }
      end
    end

    def decorate(instance, mappings)
      item = instance.to_h.deep_stringify_keys
      name = (item['name'] || item['instanceName'] || item['instanceId']).to_s
      provider = (item['integration'] || item['provider']).to_s
      mapping = mappings[name]
      status = item['connectionStatus'] || item['status'] || item['state'] || item.dig('instance', 'state')
      status = status['state'] if status.is_a?(Hash)
      owned = mapping.present? || ConnectApi::InstanceNamespace.owned?(name)

      settings = provider == CALL_PROVIDER && owned ? instance_settings(name) : {}

      {
        id: (item['id'] || item['instanceId'] || name).to_s,
        name: name,
        provider: provider,
        provider_label: provider_label(provider),
        status: status.to_s.presence || 'unknown',
        number: item['number'].presence || item['ownerJid'].to_s.split('@').first.presence,
        profile_name: item['profileName'],
        profile_picture: item['profilePicUrl'],
        calls_supported: provider == CALL_PROVIDER,
        voice_supported: provider == CALL_PROVIDER,
        voip_max_concurrent_calls: settings['voipMaxConcurrentCalls'],
        voip_max_concurrent_calls_limit: settings['voipMaxConcurrentCallsLimit'],
        hub_owned: owned,
        hub_managed: mapping.present?,
        inbox_id: mapping&.dig(:inbox)&.id,
        inbox_name: mapping&.dig(:inbox)&.name,
        account_id: mapping&.dig(:account)&.id,
        account_name: mapping&.dig(:account)&.name,
        counts: {
          contacts: item.dig('_count', 'Contact').to_i,
          conversations: item.dig('_count', 'Chat').to_i,
          messages: item.dig('_count', 'Message').to_i
        },
        updated_at: item['updatedAt']
      }
    end

    def instance_settings(instance_name)
      value = @client.find_settings(instance_name)
      value.is_a?(Hash) ? value : {}
    rescue ConnectApi::Error
      {}
    end

    def provider_label(provider)
      {
        'WHATSAPP-BAILEYS' => 'Baileys',
        'WHATSAPP-ZAPO' => 'ZAPO',
        'WHATSAPP-BUSINESS' => 'WhatsApp Business / Cloud API'
      }.fetch(provider, provider.presence || 'Desconhecido')
    end

    def connected?(status)
      %w[open connected].include?(status.to_s.downcase)
    end

    def manager_url(root)
      configured_manager_url.presence || (root.is_a?(Hash) ? root['manager'] : nil)
    end

    def configured_manager_url
      GlobalConfigService.load('CONNECT_API_MANAGER_PUBLIC_URL', ENV.fetch('CONNECT_API_MANAGER_PUBLIC_URL', '')).to_s.strip.presence
    end
  end
end
