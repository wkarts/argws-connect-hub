class Api::V1::Accounts::WhatsappGroupSettingsController < Api::V1::Accounts::BaseController
  before_action :load_inbox
  before_action :disable_caching
  rescue_from Whatsapp::Groups::Configuration::Conflict, ActiveRecord::StaleObjectError do |error|
    render json: { error: error.message }, status: :conflict
  end
  rescue_from ConnectApi::Error do |_error|
    render json: { error: 'Não foi possível confirmar a operação na Connect API. Atualize e tente novamente.' }, status: :bad_gateway
  end
  rescue_from HubDiagnostics::BindingBusy do |_error|
    render json: { error: 'Há uma operação em andamento nesta caixa. Tente novamente.' }, status: :conflict
  end

  def show
    render json: configuration_payload
  end

  def update
    raise ActionController::BadRequest, 'enabled must be boolean' if params.key?(:enabled) && ![true, false].include?(params[:enabled])
    input = params.require(:settings).permit(:selection_mode, :default_treatment, :default_access_mode, :lock_version, default_user_ids: []).to_h
    Whatsapp::Groups::Configuration.new(@inbox, Current.user).update_settings!(input, enabled: params[:enabled])
    render json: configuration_payload
  end

  def sync
    count = nil
    HubDiagnostics::ChannelLock.with(@inbox.channel_id, exclusive: true) do
      count = Whatsapp::Groups::Provider.new(@inbox).discover!
    end
    render json: configuration_payload.merge(discovered: count)
  end

  def update_group
    group = groups.find(params[:group_id])
    input = params.require(:group).permit(:selected, :treatment, :access_mode, :lock_version, allowed_user_ids: []).to_h
    Whatsapp::Groups::Configuration.new(@inbox, Current.user).update_group!(group, input, confirmed: params[:confirmed] == true)
    render json: Whatsapp::Groups::Presenter.group(group, Current.user, administrative: true)
  end

  def bulk_update
    raise ActionController::BadRequest, 'Confirme a alteração em lote.' unless params[:confirmed] == true
    inputs = params.require(:groups)
    raise ActionController::BadRequest, 'Selecione de 1 a 100 grupos.' unless inputs.is_a?(Array) && inputs.size.between?(1, 100)
    ids = inputs.map { |input| input[:id] }
    raise ActionController::BadRequest, 'Grupos duplicados.' unless ids.uniq == ids
    # Lock one channel while validating all versions, and roll back the entire
    # batch on conflict. No changes to provider settings in this operation.
    result = []
    notifications = []
    HubDiagnostics::ChannelLock.with(@inbox.channel_id, exclusive: true) do
      WhatsappGroup.transaction do
        inputs.sort_by { |input| input[:id].to_i }.each do |input|
          group = groups.find(input[:id])
          fields = input.permit(:selected, :treatment, :access_mode, :lock_version, allowed_user_ids: []).to_h
          notifications << [group.id, group.allowed_users.ids]
          Whatsapp::Groups::Configuration.new(@inbox, Current.user).update_group!(group, fields, confirmed: true, publish: false)
          result << Whatsapp::Groups::Presenter.group(group, Current.user, administrative: true)
        end
      end
    end
    notifications.each { |id, users| Whatsapp::Groups::BroadcastJob.perform_later(id, nil, nil, users) }
    render json: { groups: result }
  end

  def replay
    raise ActionController::BadRequest, 'Confirme a importação do histórico retido.' unless params[:confirmed] == true
    group = groups.find(params[:group_id])
    Whatsapp::Groups::Lock.with(group) { Whatsapp::Groups::Router.new(@inbox).replay_pending!(group) }
    render json: Whatsapp::Groups::Presenter.group(group, Current.user, administrative: true)
  end

  private

  def load_inbox
    raise Pundit::NotAuthorizedError unless Current.user.is_a?(User)
    Current.account_user = Current.account.account_users.find_by(user_id: Current.user.id)
    raise Pundit::NotAuthorizedError unless Current.account_user
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update? # Includes administrative GET; not only show?.
    raise ActiveRecord::RecordNotFound unless @inbox.whatsapp? && @inbox.channel.provider == 'connectapi'
  end

  def groups
    WhatsappGroup.where(account_id: Current.account.id, inbox_id: @inbox.id)
  end

  def configuration_payload
    settings = WhatsappGroupSetting.for(@inbox)
    scope = groups
    if params[:q].present?
      search = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(120))}%"
      scope = scope.where('name ILIKE ? OR jid ILIKE ?', search, search)
    end
    page = [params[:page].to_i, 1].max
    { enabled: @inbox.channel.reload.groups_enabled?,
      settings: settings.slice(:selection_mode, :default_treatment, :default_access_mode, :default_user_ids, :lock_version),
      users: Whatsapp::Groups::Access.eligible_users(@inbox).order(:name).map { |user| { id: user.id, name: user.name } },
      groups: scope.order(:name, :id).offset((page - 1) * 25).limit(25).map { |group| Whatsapp::Groups::Presenter.group(group, Current.user, administrative: true) },
      total: scope.count, page: page, per_page: 25 }
  end

  def disable_caching
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
