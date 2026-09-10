# frozen_string_literal: true

class SuperAdmin::ConnectApiController < SuperAdmin::ApplicationController
  PROVIDERS = %w[WHATSAPP-BAILEYS WHATSAPP-ZAPO].freeze
  ACTIONS = %w[restart logout delete connect].freeze

  def show
    @overview = registry.overview
  end

  def instance_action
    instance_name = required_instance_name
    ensure_hub_owned!(instance_name)
    action = params[:operation].to_s
    raise ConnectApi::Error, 'Operação não permitida.' unless ACTIONS.include?(action)

    result = case action
             when 'restart' then client.restart(instance_name)
             when 'logout' then client.logout(instance_name)
             when 'connect' then client.connect(instance_name, number: params[:number])
             when 'delete' then delete_instance(instance_name)
             end

    flash[:notice] = success_message(action, instance_name, result)
  rescue ConnectApi::Error => e
    flash[:error] = e.message
  ensure
    redirect_to super_admin_connect_api_path
  end

  def migrate_provider
    instance_name = required_instance_name
    ensure_hub_owned!(instance_name)
    target_provider = params[:target_provider].to_s
    raise ConnectApi::Error, 'Provider de destino inválido.' unless PROVIDERS.include?(target_provider)

    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    result = client.migrate_provider(instance_name, target_provider: target_provider, dry_run: dry_run)
    registry.sync_provider!(instance_name, target_provider) unless dry_run || result.to_h['migrated'] == false

    flash[:notice] = if dry_run
                       "Dry-run concluído para #{instance_name} → #{target_provider}: #{compact_result(result)}"
                     else
                       "Migração solicitada para #{instance_name} → #{target_provider}: #{compact_result(result)}"
                     end
  rescue ConnectApi::Error => e
    flash[:error] = e.message
  ensure
    redirect_to super_admin_connect_api_path
  end

  def update_voip_limit
    instance_name = required_instance_name
    ensure_hub_managed!(instance_name)
    value = params[:voip_max_concurrent_calls].to_i
    raise ConnectApi::Error, 'Informe um limite de chamadas simultâneas maior que zero.' unless value.positive?

    channel = registry.managed_channel(instance_name)
    current_settings = client.find_settings(instance_name).to_h.deep_stringify_keys
    channel_config = channel.provider_config.to_h.deep_stringify_keys

    settings_payload = {
      rejectCall: boolean_setting(current_settings, 'rejectCall', false),
      groupsIgnore: boolean_setting(current_settings, 'groupsIgnore', channel_config.fetch('ignore_group_messages', true)),
      alwaysOnline: boolean_setting(current_settings, 'alwaysOnline', false),
      readMessages: boolean_setting(current_settings, 'readMessages', false),
      readStatus: boolean_setting(current_settings, 'readStatus', false),
      syncFullHistory: boolean_setting(current_settings, 'syncFullHistory', !channel_config.fetch('ignore_history_messages', true)),
      voipMaxConcurrentCalls: value
    }
    settings_payload[:msgCall] = current_settings['msgCall'] if current_settings.key?('msgCall')

    result = client.set_settings(instance_name, settings_payload)
    channel_config['voip_max_concurrent_calls'] = value
    channel.update_columns(provider_config: channel_config, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    flash[:notice] = "Limite de chamadas de #{instance_name} atualizado para #{value}. #{compact_result(result)}".strip
  rescue ConnectApi::Error => e
    flash[:error] = e.message
  ensure
    redirect_to super_admin_connect_api_path
  end

  private

  def client
    @client ||= ConnectApi::Client.new
  end

  def registry
    @registry ||= ConnectApi::HubInstanceRegistry.new(client: client)
  end

  def required_instance_name
    params[:instance_name].to_s.presence || raise(ConnectApi::Error, 'Instância é obrigatória.')
  end

  def ensure_hub_owned!(instance_name)
    return if registry.hub_owned?(instance_name)

    raise ConnectApi::Error, 'Esta instância não pertence a esta instalação do HUB.'
  end

  def ensure_hub_managed!(instance_name)
    return if registry.managed_channel(instance_name)

    raise ConnectApi::Error, 'Esta instância não está vinculada a uma caixa do HUB.'
  end

  def delete_instance(instance_name)
    ensure_delete_confirmation!(instance_name)
    result = client.delete_instance(instance_name)
    registry.mark_manually_deleted!(instance_name)
    result
  rescue ConnectApi::Error => e
    if e.status.to_i == 404
      registry.mark_manually_deleted!(instance_name)
      return { 'status' => 'already_absent' }
    end

    raise
  end

  def ensure_delete_confirmation!(instance_name)
    confirmation = params[:confirmation].to_s
    raise ConnectApi::Error, 'Confirmação de exclusão inválida.' unless confirmation == instance_name
  end

  def boolean_setting(settings, key, fallback)
    return fallback unless settings.key?(key)

    ActiveModel::Type::Boolean.new.cast(settings[key])
  end

  def success_message(action, instance_name, result)
    labels = {
      'restart' => 'reiniciada',
      'logout' => 'desconectada',
      'connect' => 'conexão solicitada',
      'delete' => 'excluída'
    }
    "Instância #{instance_name}: #{labels[action]}. #{compact_result(result)}".strip
  end

  def compact_result(result)
    return '' if result.blank?

    if result.is_a?(Hash)
      message = result['message'] || result['status'] || result.dig('instance', 'state')
      return message.to_s if message.present?
    end

    result.to_s.truncate(240)
  end
end
