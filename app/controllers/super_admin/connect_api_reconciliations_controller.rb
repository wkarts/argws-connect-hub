# frozen_string_literal: true

class SuperAdmin::ConnectApiReconciliationsController < SuperAdmin::ApplicationController
  helper HubAdminUiHelper
  before_action :private_response!
  before_action :load_channels

  def show
    @channel = selected_channel
    @operation = @channel&.provider_config.to_h['hub_reconciliation_operation'].to_h
    @default_from = 24.hours.ago.in_time_zone('America/Bahia').strftime('%Y-%m-%dT%H:%M')
    @default_to = Time.current.in_time_zone('America/Bahia').strftime('%Y-%m-%dT%H:%M')
  end

  def create
    channel = @channels.find(params[:channel_id])
    from_at = parse_bahia_time!(params[:from_at], 'Data inicial')
    to_at = parse_bahia_time!(params[:to_at], 'Data final')
    raise ArgumentError, 'A data final deve ser posterior à data inicial.' unless to_at > from_at

    enqueue_operation(
      channel,
      mode: 'range',
      from_at: from_at.utc.iso8601,
      to_at: to_at.utc.iso8601
    )

    redirect_to super_admin_connect_api_reconciliation_path(channel_id: channel.id),
                notice: 'Reconciliação por período enfileirada. Conversas resolvidas permanecerão resolvidas.'
  rescue ArgumentError => error
    redirect_to super_admin_connect_api_reconciliation_path(channel_id: params[:channel_id]),
                alert: error.message
  end

  def import_all
    channel = @channels.find(params[:channel_id])
    enqueue_operation(channel, mode: 'all')

    redirect_to super_admin_connect_api_reconciliation_path(channel_id: channel.id),
                notice: 'Importação completa enfileirada. O HUB importará somente o histórico disponível na Connect|API.'
  rescue ArgumentError => error
    redirect_to super_admin_connect_api_reconciliation_path(channel_id: params[:channel_id]),
                alert: error.message
  end

  private

  def load_channels
    @channels = Channel::Whatsapp.where(provider: 'connectapi')
                                 .includes(:inbox, :account)
                                 .order(:id)
  end

  def selected_channel
    @channels.find_by(id: params[:channel_id]) || @channels.first
  end

  def enqueue_operation(channel, mode:, from_at: nil, to_at: nil)
    current = channel.provider_config.to_h['hub_reconciliation_operation'].to_h
    if %w[queued running].include?(current['state'])
      raise ArgumentError, 'Já existe uma reconciliação em andamento para esta caixa.'
    end

    operation_id = SecureRandom.uuid
    config = channel.provider_config.to_h.deep_dup
    config['hub_reconciliation_operation'] = {
      'operation_id' => operation_id,
      'state' => 'queued',
      'mode' => mode,
      'from_at' => from_at,
      'to_at' => to_at,
      'requested_at' => Time.current.utc.iso8601,
      'actor_id' => current_super_admin.id,
      'page' => 0,
      'records_examined' => 0,
      'records_created' => 0,
      'records_updated' => 0,
      'records_skipped' => 0
    }.compact
    channel.update_columns(provider_config: config, updated_at: channel.updated_at)

    Channels::Whatsapp::ConnectApiHistoricalReconciliationJob.perform_later(
      channel.id,
      mode: mode,
      operation_id: operation_id,
      actor_id: current_super_admin.id,
      from_at: from_at,
      to_at: to_at
    )

    HubDiagnostics::Recorder.emit(
      'reconciliation.requested',
      component: 'connectapi_reconciliation',
      operation_id: operation_id,
      actor_id: current_super_admin.id,
      channel_id: channel.id,
      inbox_id: channel.inbox.id
    )
  end

  def parse_bahia_time!(value, label)
    parsed = ActiveSupport::TimeZone['America/Bahia'].parse(value.to_s)
    raise ArgumentError, "#{label} inválida." unless parsed

    parsed
  end

  def private_response!
    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['Referrer-Policy'] = 'no-referrer'
  end
end
