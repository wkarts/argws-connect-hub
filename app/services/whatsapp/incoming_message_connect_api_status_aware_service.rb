# frozen_string_literal: true

class Whatsapp::IncomingMessageConnectApiStatusAwareService < Whatsapp::IncomingMessageConnectApiService
  SUCCESS_STATUS_RANK = {
    'sent' => 1,
    'delivered' => 2,
    'read' => 3
  }.freeze

  private

  def update_message_with_status(message, status)
    next_status = status[:status].to_s
    current_status = message.status.to_s

    return apply_remote_deletion(message, status) if next_status == 'deleted'
    return if regressive_success_status?(current_status, next_status)
    return if stale_failure_status?(current_status, next_status)

    super
  end

  def apply_remote_deletion(message, status)
    return if ActiveModel::Type::Boolean.new.cast(message.content_attributes.to_h['deleted'])

    deleted_at = status[:timestamp].to_i.positive? ? Time.at(status[:timestamp].to_i).utc : Time.current.utc
    attributes = message.content_attributes.to_h.deep_dup.merge(
      'deleted' => true,
      'deleted_for_everyone' => true,
      'deleted_at' => deleted_at.iso8601,
      'deleted_source' => 'whatsapp_remote'
    )

    ActiveRecord::Base.transaction do
      message.update!(
        content: "⛔#{I18n.t('conversations.messages.deleted')}",
        content_attributes: attributes
      )
      message.attachments.destroy_all
    end

    HubDiagnostics::Recorder.emit(
      'message.remote_deleted',
      HubDiagnostics::Recorder.message_attributes(message).merge(
        component: 'connectapi_message_revoke',
        source_id: message.source_id,
        direction: message.outgoing? ? 'outbound' : 'inbound'
      )
    )
  end

  def regressive_success_status?(current_status, next_status)
    current_rank = SUCCESS_STATUS_RANK[current_status]
    next_rank = SUCCESS_STATUS_RANK[next_status]
    current_rank.present? && next_rank.present? && next_rank <= current_rank
  end

  def stale_failure_status?(current_status, next_status)
    return false unless next_status == 'failed'

    SUCCESS_STATUS_RANK.fetch(current_status, 0) >= SUCCESS_STATUS_RANK.fetch('delivered')
  end
end
