class Webhooks::WhatsappEventsJob < ApplicationJob
  queue_as :low
  self.log_arguments = false
  retry_on ActiveRecord::RecordNotFound, wait: 30.seconds, attempts: 5
  retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 24

  def perform(params = {})
    channel = find_channel_from_whatsapp_business_payload(params)
    if channel_is_inactive?(channel)
      HubDiagnostics::Recorder.emit(
        'webhook.skipped',
        level: 'warn',
        component: 'connectapi_ingestion',
        channel_id: channel&.id,
        reason: 'channel_missing_or_inactive'
      )
      return
    end

    connect_api = channel.provider == 'connectapi'
    if connect_api
      HubDiagnostics::Recorder.emit(
        'webhook.processing_started',
        component: 'connectapi_ingestion',
        account_id: channel.account_id,
        inbox_id: channel.inbox&.id,
        channel_id: channel.id,
        instance_name: channel.provider_config.to_h['instance_name']
      )
    end

    case channel.provider
    when 'whatsapp_cloud'
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
    when 'connectapi'
      Whatsapp::IncomingMessageConnectApiStatusAwareService.new(inbox: channel.inbox, params: params).perform
    else
      Whatsapp::IncomingMessageService.new(inbox: channel.inbox, params: params).perform
    end

    if connect_api
      HubDiagnostics::Recorder.emit(
        'webhook.processing_completed',
        component: 'connectapi_ingestion',
        account_id: channel.account_id,
        inbox_id: channel.inbox&.id,
        channel_id: channel.id,
        instance_name: channel.provider_config.to_h['instance_name']
      )
    end
  rescue StandardError => error
    HubDiagnostics::Recorder.error(
      'webhook.processing_failed',
      error,
      component: 'connectapi_ingestion',
      channel_id: channel&.id
    )
    raise
  end

  private

  def channel_is_inactive?(channel)
    return true if channel.blank?
    return true if channel.reauthorization_required?
    return true unless channel.account.active?

    false
  end

  def find_channel_by_url_param(params)
    return unless params[:phone_number]

    Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  def find_channel_from_whatsapp_business_payload(params)
    # for the case where facebook cloud api support multiple numbers for a single app
    # compatibility note#issuecomment-1173838350
    # we will give priority to the phone_number in the payload
    return get_channel_from_wb_payload(params) if params[:object] == 'whatsapp_business_account'

    find_channel_by_url_param(params)
  end

  def get_channel_from_wb_payload(wb_params)
    phone_number = "+#{wb_params[:entry].first[:changes].first.dig(:value, :metadata, :display_phone_number)}"
    phone_number_id = wb_params[:entry].first[:changes].first.dig(:value, :metadata, :phone_number_id)
    channel = Channel::Whatsapp.find_by(phone_number: phone_number)
    # validate to ensure the phone number id matches the whatsapp channel
    return channel if channel && channel.provider_config['phone_number_id'] == phone_number_id
  end
end