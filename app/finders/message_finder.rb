class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  # Message ids are insertion ids, not timeline cursors. Historical reconciliation
  # can insert an old message today, giving it a larger id than newer messages.
  # Resolve the id to its timestamp and paginate by (created_at, id) instead.
  def messages_after(after_id)
    cursor = cursor_message(after_id)
    return messages.reorder(created_at: :asc, id: :asc).where('id > ?', after_id).limit(100) unless cursor

    messages
      .reorder(created_at: :asc, id: :asc)
      .where(
        'created_at > ? OR (created_at = ? AND id > ?)',
        cursor.created_at,
        cursor.created_at,
        cursor.id
      )
      .limit(100)
  end

  def messages_before(before_id)
    cursor = cursor_message(before_id)
    scope = if cursor
              messages.where(
                'created_at < ? OR (created_at = ? AND id < ?)',
                cursor.created_at,
                cursor.created_at,
                cursor.id
              )
            else
              messages.where('id < ?', before_id)
            end

    scope.reorder(created_at: :desc, id: :desc).limit(20).reverse
  end

  # This dual-bound form is also used by the reply-to lookup with id +/- 1.
  # Keep the id range semantics for compatibility, but return the records in
  # deterministic chronological order.
  def messages_between(after_id, before_id)
    messages
      .reorder(created_at: :asc, id: :asc)
      .where('id >= ? AND id < ?', after_id, before_id)
      .limit(1000)
  end

  def messages_latest
    messages.reorder(created_at: :desc, id: :desc).limit(20).reverse
  end

  def cursor_message(id)
    @conversation.messages.find_by(id: id)
  end
end
