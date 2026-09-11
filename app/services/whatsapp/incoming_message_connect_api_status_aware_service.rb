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

    return if regressive_success_status?(current_status, next_status)
    return if stale_failure_status?(current_status, next_status)

    super
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
