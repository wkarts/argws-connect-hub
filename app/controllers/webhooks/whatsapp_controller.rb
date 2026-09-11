class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  def process_payload
    if connect_api_call_payload?
      channel = find_connect_api_channel
      return head :not_found if channel.blank?
      return head :unauthorized unless valid_connect_api_call_webhook?(channel)

      Webhooks::ConnectApiCallEventsJob.perform_later(params.to_unsafe_hash, channel.id)
      return head :accepted
    end

    Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  def connect_api_call_payload?
    params[:event].to_s.casecmp('call').zero? && params[:data].present?
  end

  def find_connect_api_channel
    raw_phone = params[:phone_number].to_s
    digits = raw_phone.gsub(/\D/, '')

    Channel::Whatsapp.find_by(phone_number: raw_phone, provider: 'connectapi') ||
      Channel::Whatsapp.find_by(phone_number: "+#{digits}", provider: 'connectapi')
  end

  def valid_connect_api_call_webhook?(channel)
    config = channel.provider_config.to_h.deep_stringify_keys
    expected_token = config['api_key'].to_s
    provided_token = request.headers['X-Connect-Hub-Token'].to_s
    expected_instance = config['instance_name'].to_s
    provided_instance = params[:instance].to_s

    return false if expected_token.blank? || provided_token.blank?
    return false unless expected_token.bytesize == provided_token.bytesize
    return false unless expected_instance.present? && ActiveSupport::SecurityUtils.secure_compare(expected_instance, provided_instance)

    ActiveSupport::SecurityUtils.secure_compare(expected_token, provided_token)
  end

  def valid_token?(token)
    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
  end
end