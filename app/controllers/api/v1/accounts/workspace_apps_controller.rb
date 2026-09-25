class Api::V1::Accounts::WorkspaceAppsController < Api::V1::Accounts::BaseController
  before_action :require_membership
  before_action :check_admin_authorization?, only: [:manage, :create, :update, :destroy]
  before_action :fetch_app, only: [:show, :update, :destroy, :credential, :forget_credential, :launch]
  before_action :require_interactive_user, only: [:credential, :forget_credential, :launch]
  before_action :disable_caching

  def index
    apps = Current.account.workspace_apps.where(enabled: true).with_attached_icon.ordered
    render json: apps.select { |app| app.accessible_to?(Current.account_user) }.map { |app| app_payload(app) }
  end

  def manage
    render json: Current.account.workspace_apps.with_attached_icon.ordered.map { |app| app_payload(app, administrative: true) }
  end

  def show
    return unless authorize_app

    render json: app_payload(@app)
  end

  def create
    @app = Current.account.workspace_apps.new(app_params)
    return unless safe_hub_origin?

    @app.save!
    render json: app_payload(@app, administrative: true), status: :created
  end

  def update
    @app.assign_attributes(app_params)
    return unless safe_hub_origin?

    @app.save!
    @app.icon.purge_later if ActiveModel::Type::Boolean.new.cast(params.dig(:workspace_app, :remove_icon))
    render json: app_payload(@app, administrative: true)
  end

  def destroy
    @app.destroy!
    head :no_content
  end

  def credential
    return unless authorize_app

    saved = @app.workspace_app_credentials.find_by(account_user: Current.account_user)
    data = @app.allow_saved_credentials? ? saved&.credentials : nil
    render json: {
      saved: data.present?, username: data&.fetch('username', ''),
      auto_login: data.present? && @app.allow_auto_login? && saved.auto_login?,
      integration_revision: @app.integration_revision
    }
  end

  def forget_credential
    return unless authorize_app(require_enabled: false)

    @app.workspace_app_credentials.where(account_user: Current.account_user).destroy_all
    head :no_content
  end

  # Only this explicit, interactive POST returns credentials to their owner for
  # an authorized browser form submission. No API token or HUB session is sent
  # to the destination, and no backend HTTP request to an arbitrary URL occurs.
  def launch
    return unless authorize_app
    return render_error('post_authentication_required') unless @app.auth_mode == 'form_post'

    @app.with_lock do
      return unless authorize_app
      return render_error('application_configuration_changed', :conflict) unless
        params[:integration_revision] == @app.integration_revision

      payload = launch_credentials
      return if performed?

      render json: {
        action: @app.login_url, username_field: @app.username_field, password_field: @app.password_field,
        username: payload.fetch('username'), password: payload.fetch('password'),
        integration_revision: @app.integration_revision
      }
    end
  end

  private

  def require_membership
    render json: { error: 'forbidden' }, status: :forbidden unless Current.account_user && Current.user
  end

  def require_interactive_user
    if authenticate_by_access_token? || !current_user || request.headers['access-token'].blank?
      render json: { error: 'interactive_login_required' }, status: :forbidden
    end
  end

  def disable_caching
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Referrer-Policy'] = 'no-referrer'
  end

  def fetch_app
    @app = Current.account.workspace_apps.find(params[:id])
  end

  def authorize_app(require_enabled: true)
    return true if @app.accessible_to?(Current.account_user) && (!require_enabled || @app.enabled?)

    render json: { error: 'application_unavailable' }, status: :forbidden
    false
  end

  def safe_hub_origin?
    return true unless @app.launch_mode == 'embedded' && @app.origin(@app.url) == @app.origin(request.base_url) && @app.origin(@app.url)

    render_error('hub_origin_cannot_be_embedded')
    false
  end

  def launch_credentials
    input = params[:workspace_credentials]
    if input.present?
      return render_error('invalid_credentials') unless input.is_a?(ActionController::Parameters)

      data = input.permit(:username, :password, :remember, :auto_login)
      username = data[:username]
      password = data[:password]
      unless username.is_a?(String) && username.length.between?(1, 512) && password.is_a?(String) && password.length.between?(1, 4096)
        render_error('invalid_credentials')
        return
      end
      payload = { 'username' => username, 'password' => password }
      if ActiveModel::Type::Boolean.new.cast(data[:remember])
        return render_error('credential_storage_disabled') unless @app.allow_saved_credentials?

        saved = @app.workspace_app_credentials.find_or_initialize_by(account_user: Current.account_user)
        saved.credentials = payload
        saved.auto_login = @app.allow_auto_login? && ActiveModel::Type::Boolean.new.cast(data[:auto_login])
        saved.save!
      end
      return payload
    end

    saved = @app.workspace_app_credentials.find_by(account_user: Current.account_user)
    payload = @app.allow_saved_credentials? ? saved&.credentials : nil
    return payload if payload.present?

    render_error('credentials_required')
    nil
  end

  def render_error(code, status = :unprocessable_entity)
    render json: { error: code }, status: status
  end

  def app_params
    permitted = params.require(:workspace_app).permit(
      :name, :url, :icon_name, :icon, :enabled, :position, :launch_mode, :auth_mode, :login_url,
      :username_field, :password_field, :allow_saved_credentials, :allow_auto_login, :access_mode,
      allowed_user_ids: []
    )
    if permitted[:icon].present? && !permitted[:icon].is_a?(ActionDispatch::Http::UploadedFile)
      raise ActionController::ParameterMissing, :icon_file
    end
    if permitted.key?(:allowed_user_ids)
      permitted[:allowed_user_ids] = permitted[:allowed_user_ids].reject(&:blank?).map do |id|
        id.is_a?(String) && id.match?(/\A[1-9]\d*\z/) ? id.to_i : id
      end
    end
    permitted
  end

  def app_payload(app, administrative: false)
    data = app.slice(:id, :name, :url, :icon_name, :enabled, :position, :launch_mode, :auth_mode,
                     :login_url, :username_field, :password_field, :allow_saved_credentials, :allow_auto_login)
    data[:icon_url] = app.icon.attached? ? rails_blob_path(app.icon, only_path: true) : nil
    data[:integration_revision] = app.integration_revision
    if administrative
      data[:access_mode] = app.access_mode
      data[:allowed_user_ids] = app.allowed_user_ids
    end
    data
  end
end
