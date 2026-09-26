class Api::V1::Accounts::WhatsappGroupMessagesController < Api::V1::Accounts::BaseController
  before_action :load_group
  before_action :disable_caching
  rescue_from Whatsapp::Groups::Configuration::Conflict do |error|
    render json: { error: error.message }, status: :conflict
  end
  rescue_from HubDiagnostics::BindingBusy do |_error|
    render json: { error: 'Há uma operação em andamento neste grupo. Tente novamente.' }, status: :conflict
  end
  rescue_from ConnectApi::Error do |_error|
    render json: { error: 'A Connect API não confirmou a operação. Confira antes de tentar novamente.' }, status: :bad_gateway
  end

  def index
    scope = @group.whatsapp_group_messages
    scope = scope.where('id < ?', params[:before].to_i) if params[:before].present?
    records = scope.order(id: :desc).limit(50).to_a
    render json: { messages: records.reverse.map { |message| Whatsapp::Groups::Presenter.message(message, Current.user) },
                   next_before: records.size == 50 ? records.last.id : nil }
  end

  def show
    render json: Whatsapp::Groups::Presenter.message(@group.whatsapp_group_messages.find(params[:id]), Current.user)
  end

  def create
    input = params.require(:group_message).permit(:client_id, :content, :file, :reply_to_source_id)
    raise ActionController::BadRequest, 'client_id inválido' unless input[:client_id].to_s.match?(/\A[0-9a-f-]{36}\z/i)
    content = input[:content].to_s
    upload = input[:file]
    raise ActionController::BadRequest, 'Arquivo inválido' if upload.present? && !upload.is_a?(ActionDispatch::Http::UploadedFile)
    raise ActionController::BadRequest, 'Escreva uma mensagem ou selecione um arquivo.' if content.blank? && upload.blank?
    raise ActionController::BadRequest, 'A mensagem excede o limite permitido.' if content.length > 65_536 || (upload && upload.size > WhatsappGroupMessage::MAX_FILE_BYTES)
    message = nil
    Whatsapp::Groups::Lock.with(@group) do
      require_writable!
      message = @group.whatsapp_group_messages.find_by(client_id: input[:client_id])
      if message
        raise Pundit::NotAuthorizedError unless message.user_id == Current.user.id
      else
        reply = input[:reply_to_source_id].presence
        @group.whatsapp_group_messages.find_by!(source_id: reply) if reply
        message = @group.whatsapp_group_messages.new(client_id: input[:client_id], direction: 'outgoing', status: 'queued',
          kind: upload ? media_kind(upload.content_type) : 'text', content: content.presence, user: Current.user,
          reply_to_source_id: reply, sent_at: Time.current, policy_version: @group.policy_version)
        message.files.attach(upload) if upload
        message.save!
      end
    end
    Whatsapp::Groups::SendJob.perform_later(message.id) if message.status == 'queued'
    render json: Whatsapp::Groups::Presenter.message(message, Current.user), status: :created
  end

  def destroy
    message = @group.whatsapp_group_messages.find(params[:id])
    Whatsapp::Groups::Lock.with(@group) do
      message.reload
      raise Pundit::NotAuthorizedError unless @group.active? && @group.allowed?(Current.user)
      permitted = message.outgoing? && (message.user_id == Current.user.id || Current.account_user.administrator?)
      raise Pundit::NotAuthorizedError unless permitted
      return head :no_content if message.deleted_at
      raise Whatsapp::Groups::Configuration::Conflict, 'Confirme o envio pendente antes de apagar.' if %w[sending uncertain].include?(message.status)
      if message.source_id.present?
        raise Whatsapp::Groups::Configuration::Conflict, 'A instância desta mensagem não é mais a instância da caixa.' unless message.binding_token == Whatsapp::Groups::Provider.binding_token(@group.inbox)
        Whatsapp::Groups::Provider.new(@group.inbox).revoke!(message)
      end
      Whatsapp::Groups::Status.apply!(message, 'deleted')
    end
    head :no_content
  end

  def cancel
    message = @group.whatsapp_group_messages.find(params[:id])
    Whatsapp::Groups::Lock.with(@group) do
      message.reload
      raise Pundit::NotAuthorizedError unless @group.active? && @group.allowed?(Current.user)
      raise Pundit::NotAuthorizedError unless message.user_id == Current.user.id || Current.account_user.administrator?
      raise ActionController::BadRequest, 'Confirme que verificou a entrega no WhatsApp.' unless params[:confirmed] == true
      raise Whatsapp::Groups::Configuration::Conflict, 'O envio já está confirmado.' if message.source_id.present?
      # Cancellation acknowledges uncertainty, it does not revoke a message
      # potentially delivered by the provider and never automatically resends.
      message.update!(status: 'failed', external_error: 'Envio encerrado manualmente após conferência no WhatsApp.')
    end
    render json: Whatsapp::Groups::Presenter.message(message, Current.user)
  end

  private

  def load_group
    raise Pundit::NotAuthorizedError unless Current.user.is_a?(User)
    Current.account_user = Current.account.account_users.find_by(user_id: Current.user.id)
    raise Pundit::NotAuthorizedError unless Current.account_user
    @group = Whatsapp::Groups::Access.scope(Current.user, Current.account, active: true).find(params[:whatsapp_group_id])
  end

  def require_writable!
    raise Whatsapp::Groups::Configuration::Conflict, 'O tratamento do grupo mudou. Atualize a conversa.' unless @group.management?
    raise Pundit::NotAuthorizedError unless @group.active? && @group.allowed?(Current.user)
  end

  def media_kind(content_type)
    prefix = content_type.to_s.split('/').first
    %w[image video audio].include?(prefix) ? prefix : 'document'
  end

  def disable_caching
    response.headers['Cache-Control'] = 'private, no-store'
  end
end
