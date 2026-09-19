# frozen_string_literal: true

require 'cgi'
require 'uri'

class Whatsapp::ConnectApiRealtimeWebhookService
  def initialize(channel:)
    @channel = channel
    @config = channel.provider_config.to_h.deep_stringify_keys
  end

  def ensure!
    return :skipped unless eligible?

    remote = fetch_remote
    validate_identity!(remote)

    if webhook_matches?(remote)
      HubDiagnostics::Recorder.emit('webhook.health_ok', diagnostic_context)
      return :ok
    end

    client.request(
      :put,
      compatibility_path,
      body: { enabled: true, webhookUrl: expected_webhook_url(remote['phoneNumberId']) },
      timeout: 10
    )

    verified = fetch_remote
    validate_identity!(verified)
    raise ConnectApi::Error, 'Connect|API webhook repair was not persisted' unless webhook_matches?(verified)

    persist_verified_metadata(verified)
    HubDiagnostics::Recorder.emit(
      'webhook.health_repaired',
      diagnostic_context.merge(reason: 'webhook_url_reconciled')
    )
    :repaired
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'webhook.health_failed',
      error,
      diagnostic_context.merge(reason: 'realtime_webhook_unhealthy')
    )
    :failed
  end

  private

  def eligible?
    return false unless @channel.provider == 'connectapi'
    return false if ActiveModel::Type::Boolean.new.cast(@config['connect_api_manual_deletion'])

    instance_name.present? && @channel.inbox.present?
  end

  def fetch_remote
    response = client.request(:get, compatibility_path, timeout: 10)
    raise ConnectApi::Error, 'Connect|API returned an invalid Meta compatibility response' unless response.is_a?(Hash)

    response.deep_stringify_keys
  end

  def validate_identity!(remote)
    local_phone = @channel.phone_number.to_s.gsub(/\D/, '')
    local_phone_id = @config['phone_number_id'].to_s
    remote_phone = remote['displayPhoneNumber'].to_s.gsub(/\D/, '')
    remote_phone_id = remote['phoneNumberId'].to_s

    phone_matches = remote_phone.present? && remote_phone == local_phone
    phone_id_matches = local_phone_id.present? && remote_phone_id.present? && local_phone_id == remote_phone_id
    return if phone_matches || phone_id_matches

    raise ConnectApi::Error, 'Connect|API instance identity does not match this HUB channel'
  end

  def webhook_matches?(remote)
    normalize_url(remote['webhookUrl']) == normalize_url(expected_webhook_url(remote['phoneNumberId']))
  end

  def expected_webhook_url(remote_phone_id = nil)
    frontend = ENV.fetch('FRONTEND_URL', '').to_s.sub(%r{/+$}, '')
    uri = URI.parse(frontend)
    unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      raise ConnectApi::Error, 'FRONTEND_URL is invalid for Connect|API realtime webhook'
    end

    phone_id = remote_phone_id.to_s.presence ||
               @config['phone_number_id'].to_s.presence ||
               @channel.phone_number.to_s.gsub(/\D/, '')
    base = "#{frontend}/webhooks/whatsapp/#{phone_id}"
    binding_ref = @config['hub_binding_ref'].to_s
    binding_ref.present? ? "#{base}?hub_binding_ref=#{CGI.escape(binding_ref)}" : base
  rescue URI::InvalidURIError
    raise ConnectApi::Error, 'FRONTEND_URL is invalid for Connect|API realtime webhook'
  end

  def normalize_url(value)
    value.to_s.sub(%r{/+$}, '')
  end

  def compatibility_path
    "/compat/meta/#{CGI.escape(instance_name)}"
  end

  def instance_name
    @config['instance_name'].to_s
  end

  def client
    @client ||= if @config['connect_api_binding_mode'] == 'existing'
                  ConnectApi::BoundInstanceClient.new(api_key: @config['api_key'], timeout: 10)
                else
                  ConnectApi::Client.new(timeout: 10)
                end
  end

  def persist_verified_metadata(remote)
    @channel.reload
    config = @channel.provider_config.to_h.deep_dup
    config['meta_webhook_url'] = expected_webhook_url(remote['phoneNumberId'])
    config['meta_compatible'] = true
    config['meta_compatible_verified'] = true
    config['meta_compatible_verified_at'] = Time.current.utc.iso8601
    config['communication_ready'] = true
    config['phone_number_id'] = remote['phoneNumberId'].to_s if remote['phoneNumberId'].present?
    config['business_account_id'] = remote['businessAccountId'].to_s if remote['businessAccountId'].present?
    config['display_phone_number'] = remote['displayPhoneNumber'].to_s if remote['displayPhoneNumber'].present?
    @channel.update_columns(provider_config: config, updated_at: @channel.updated_at)
  end

  def diagnostic_context
    {
      component: 'connectapi_realtime',
      account_id: @channel.account_id,
      inbox_id: @channel.inbox&.id,
      channel_id: @channel.id,
      instance_name: instance_name,
      provider: @config['connect_api_provider']
    }.compact
  end
end
