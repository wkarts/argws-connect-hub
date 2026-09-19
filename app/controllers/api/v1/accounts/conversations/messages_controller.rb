class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def destroy
    return head :bad_request unless message.can_delete_message?

    revoked_for_everyone = revoke_connect_api_message_if_needed!

    ActiveRecord::Base.transaction do
      message.update!(
        content: "⛔#{I18n.t('conversations.messages.deleted')}",
        content_attributes: {
          deleted: true,
          deleted_for_everyone: revoked_for_everyone,
          deleted_at: Time.current.utc.iso8601
        }.compact
      )
      message.attachments.destroy_all
    end
  rescue Whatsapp::ConnectApiMessageRevokeService::Error => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def retry
    return if message.blank?

    message.update!(status: :sent, content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  def forward
    contacts = forward_contact_ids
    return render json: { error: 'Selecione pelo menos um destinatário.' }, status: :unprocessable_entity if contacts.empty?
    return render json: { error: 'Um dos destinatários não pertence a esta conta.' }, status: :unprocessable_entity unless valid_forward_contacts?(contacts)

    operation_id = SecureRandom.uuid
    payload = forward_message_params.merge(
      contacts: contacts,
      operation_id: operation_id
    )

    if contacts.one?
      result = ::Conversations::ForwardMessageJob.perform_now(payload).first
      return render json: {
        status: 'forwarded',
        destination_count: 1,
        operation_id: operation_id,
        destination: result
      }
    end

    job = ::Conversations::ForwardMessageJob.perform_later(payload)
    render json: {
      status: 'queued',
      destination_count: contacts.length,
      operation_id: operation_id,
      job_id: job.job_id
    }, status: :accepted
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Um dos destinatários não pertence a esta conta.' }, status: :unprocessable_entity
  rescue StandardError => error
    Rails.logger.error("[HUB forward] #{error.class}: #{error.message}")
    render json: { error: 'Não foi possível encaminhar a mensagem. Tente novamente.' }, status: :unprocessable_entity
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def revoke_connect_api_message_if_needed!
    return false unless Whatsapp::ConnectApiMessageRevokeService.applicable?(message)

    Whatsapp::ConnectApiMessageRevokeService.new(message: message).perform!
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  def forward_contact_ids
    Array(params[:contacts]).map(&:to_i).select(&:positive?).uniq
  end

  def valid_forward_contacts?(contact_ids)
    Current.account.contacts.where(id: contact_ids).count == contact_ids.length
  end

  def forward_message_params
    {
      user_id: Current.user.id,
      account_id: Current.account.id,
      message_id: message.id
    }
  end
end
