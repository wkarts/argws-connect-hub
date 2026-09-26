# frozen_string_literal: true

require 'cgi'

# Runs only after an explicit change of the inbox group opt-in. No polling,
# session recreation, webhook replacement or changes to another repository.
class Whatsapp::ConnectApiGroupSettingsService
  BOOLEAN_SETTINGS = %w[rejectCall groupsIgnore alwaysOnline readMessages readStatus syncFullHistory].freeze

  def initialize(channel)
    @channel = channel
  end

  def sync!
    config = @channel.provider_config.to_h
    instance = config.fetch('instance_name').to_s
    client = if config['connect_api_binding_mode'] == 'existing'
               ConnectApi::BoundInstanceClient.new(api_key: config.fetch('api_key'), timeout: 10)
             else
               ConnectApi::Client.new(timeout: 10)
             end
    path = "/settings/#{CGI.escape(instance)}"
    remote = client.request(:get, path.sub('/settings/', '/settings/find/'))
    unless remote.is_a?(Hash) && BOOLEAN_SETTINGS.all? { |key| [true, false].include?(remote[key]) }
      raise ConnectApi::Error, 'A API não retornou as configurações completas da instância; nenhuma opção foi sobrescrita.'
    end
    desired = !@channel.groups_enabled?
    return true if remote['groupsIgnore'] == desired

    payload = remote.slice(*BOOLEAN_SETTINGS, 'msgCall', 'voipMaxConcurrentCalls').merge('groupsIgnore' => desired)
    client.request(:post, path.sub('/settings/', '/settings/set/'), body: payload)
    verified = client.request(:get, path.sub('/settings/', '/settings/find/'))
    unless verified.is_a?(Hash) && verified['groupsIgnore'] == desired
      raise ConnectApi::Error, 'A API não confirmou a configuração de grupos. Atualize o status antes de tentar novamente.'
    end
    true
  end
end
