# frozen_string_literal: true

class Api::V1::Accounts::ConnectApiTemplatesController < Api::V1::Accounts::BaseController
  before_action :fetch_channel

  def show
    render_catalog
  end

  def update
    Whatsapp::ConnectApiTemplateSyncService.new(@channel).set_enabled!(
      name: params.require(:name), language: params.require(:language), enabled: params[:enabled]
    )
    render_catalog
  rescue ConnectApi::OpeningTemplateCatalog::TemplateNotFound => e
    render json: { message: e.message }, status: :not_found
  rescue ArgumentError => e
    render json: { message: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_channel
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
    authorize @inbox, :update?
    @channel = @inbox.channel
    return if @inbox.whatsapp? && @channel.provider == 'connectapi'

    render json: { message: 'Esta caixa não utiliza a Connect|API.' }, status: :unprocessable_entity
  end

  def render_catalog
    catalog = @channel.opening_template_catalog
    render json: {
      payload: catalog.entries,
      last_synced_at: @channel.message_templates_last_updated,
      message_templates: catalog.available_templates,
      opening_templates: catalog.available_templates(opening_only: true)
    }
  end
end
