module Enterprise::Account::ConversationsResolutionSchedulerJob
  def perform
    super
    resolve_response_bot_conversations
    resolve_captain_conversations
  end

  private

  def resolve_response_bot_conversations
    Account.feature_response_bot.find_each(batch_size: 100) do |account|
      account.inboxes.each do |inbox|
        Captain::InboxPendingConversationsResolutionJob.perform_later(inbox) if inbox.response_bot_enabled?
      end
    end
  end

  def resolve_captain_conversations
    Integrations::Hook.where(app_id: 'captain').find_each(batch_size: 100) do |hook|
      next unless hook.enabled?

      Inbox.where(id: hook.settings['inbox_ids'].to_s.split(',')).find_each do |inbox|
        Captain::InboxPendingConversationsResolutionJob.perform_later(inbox)
      end
    end
  end
end
