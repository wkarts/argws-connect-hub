# frozen_string_literal: true

class Whatsapp::ConnectApiOpeningMessageValidator
  class Error < StandardError; end

  def initialize(message)
    @message = message
  end

  def validate!
    return unless applicable?

    params = @message.additional_attributes.to_h['template_params']
    opening = opening_message?
    return if !opening && params.blank?

    template = params.is_a?(Hash) && current_catalog.find_available(
      name: params['name'], language: params['language'], opening_only: opening
    )
    unless template
      raise Error, 'Escolha um template habilitado e disponível nesta caixa para iniciar a conversa.'
    end
    if template['origin'] == 'CONNECT_LOCAL' &&
       (params['connect_template_id'] != template['id'] || params['connect_template_revision'] != template['revision'])
      raise Error, 'O modelo foi alterado. Atualize o catálogo e selecione-o novamente.'
    end
  end

  private

  def channel
    @message.inbox.channel
  end

  def current_catalog
    # Reload choices for queued/retried messages, not a cached association.
    Channel::Whatsapp.find(channel.id).opening_template_catalog
  end

  def applicable?
    return false unless (@message.outgoing? || @message.template?) && !@message.private?

    @message.inbox.whatsapp? && channel.provider == 'connectapi'
  end

  def opening_message?
    messages = @message.conversation.messages.where(private: false)
    messages = messages.where('id < ?', @message.id) if @message.persisted?
    incoming = messages.where(message_type: :incoming)
    # A failed/queued opener does not authorize a free-text fallback.
    delivered = messages.where(message_type: :outgoing).where.not(source_id: [nil, '']).where.not(status: :failed)
    !incoming.or(delivered).exists?
  end
end
