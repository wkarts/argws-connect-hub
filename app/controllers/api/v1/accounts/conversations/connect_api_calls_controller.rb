# frozen_string_literal: true

class Api::V1::Accounts::Conversations::ConnectApiCallsController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_user!
  before_action :connect_api_channel!

  def show
    render json: {
      enabled: true,
      capabilities: call_service.capabilities,
      calls: call_service.list
    }
  rescue ConnectApi::Error => e
    render_connect_api_error(e)
  end

  def create
    render json: call_service.offer(
      number: @conversation.contact.phone_number,
      is_video: permitted_params[:is_video],
      call_duration: permitted_params[:call_duration]
    ), status: :created
  rescue ConnectApi::Error => e
    render_connect_api_error(e)
  end

  def accept
    render json: call_service.accept(permitted_params[:call_id])
  rescue ConnectApi::Error => e
    render_connect_api_error(e)
  end

  def reject
    render json: call_service.reject(permitted_params[:call_id])
  rescue ConnectApi::Error => e
    render_connect_api_error(e)
  end

  def end_call
    render json: call_service.end_call(permitted_params[:call_id])
  rescue ConnectApi::Error => e
    render_connect_api_error(e)
  end

  def mute
    render json: call_service.mute(permitted_params[:call_id], muted: permitted_params[:muted])
  rescue ConnectApi::Error => e
    render_connect_api_error(e)
  end

  def media_ticket
    render json: call_service.media_ticket(permitted_params[:call_id])
  rescue ConnectApi::Error => e
    render_connect_api_error(e)
  end

  private

  def ensure_user!
    return if Current.user.is_a?(User)

    render json: { error: 'Somente usuários do HUB podem controlar chamadas.' }, status: :forbidden
  end

  def connect_api_channel!
    @whatsapp_channel = @conversation.inbox.channel
    return if @whatsapp_channel.is_a?(Channel::Whatsapp) && @whatsapp_channel.provider == 'connectapi'

    render json: { error: 'Esta conversa não pertence a uma caixa WhatsApp Connect|API.' }, status: :unprocessable_entity
  end

  def call_service
    @call_service ||= Whatsapp::ConnectApiCallService.new(
      whatsapp_channel: @whatsapp_channel,
      contact_phone: @conversation.contact.phone_number
    )
  end

  def permitted_params
    params.permit(:call_id, :muted, :is_video, :call_duration)
  end

  def render_connect_api_error(error)
    status = error.status.to_i
    status = :unprocessable_entity unless status.between?(400, 599)
    render json: { error: error.message }, status: status
  end
end
