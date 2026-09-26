# frozen_string_literal: true
require 'cgi'
class ConnectApi::ExternalInstanceConfiguration
  # Existing bindings are READ-ONLY during normal channel validation/reconciliation.
  # No create, connect, QR, settings change, metadata rename, webhook overwrite or session deletion.
  def self.refresh(channel)
    config = channel.provider_config.to_h.deep_dup
    token = config['api_key'].to_s
    raise ArgumentError if token.blank? || config['instance_name'].blank?
    client = ConnectApi::BoundInstanceClient.new(api_key: token, timeout: 10)
    meta = client.request(:get, "/compat/meta/#{CGI.escape(config['instance_name'])}").to_h
    unless meta['enabled'] == true && meta['webhookUrl'].to_s == config['meta_webhook_url'].to_s &&
           meta['phoneNumberId'].to_s == config['phone_number_id'].to_s &&
           meta['displayPhoneNumber'].to_s.gsub(/D/, '') == channel.phone_number.to_s.gsub(/D/, '')
      channel.errors.add(:provider_config, 'O vínculo externo mudou. Valide a instância no HUB Admin.')
      return false
    end
    config['communication_ready'] = true
    config['meta_compatible_verified_at'] = Time.current.utc.iso8601
    channel.provider_config = config
    true
  rescue StandardError => error
    HubDiagnostics::Recorder.error('binding.external_validation_failed', error, channel_id: channel.id)
    channel.errors.add(:provider_config, 'Não foi possível validar a instância existente. Nenhuma sessão foi criada ou alterada.')
    false
  end
end
