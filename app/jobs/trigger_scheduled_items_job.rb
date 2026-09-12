class TriggerScheduledItemsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    # Recovery scanner for scheduled campaigns. Direct delayed jobs are queued
    # when the campaign is created/updated; this pass guarantees recovery after
    # worker restarts or queue interruptions without dropping older campaigns.
    Campaign.where(campaign_status: :active, enabled: true)
            .where.not(scheduled_at: nil)
            .where('scheduled_at <= ?', Time.current)
            .find_each(batch_size: 100) do |campaign|
      next unless campaign.scheduled_delivery?

      Campaigns::TriggerCampaignJob.perform_later(campaign.id, campaign.scheduled_at.iso8601(6))
    end

    # Job to reopen snoozed conversations
    Conversations::ReopenSnoozedConversationsJob.perform_later

    # Job to reopen snoozed notifications
    Notification::ReopenSnoozedNotificationsJob.perform_later

    # Job to auto-resolve conversations
    Account::ConversationsResolutionSchedulerJob.perform_later

    # Job to reconcile Connect|API communication settings for existing inboxes
    Channels::Whatsapp::ConnectApiProvisioningSchedulerJob.perform_later

    # Job to sync whatsapp templates
    Channels::Whatsapp::TemplatesSyncSchedulerJob.perform_later

    # Job to clear notifications which are older than 1 month
    Notification::RemoveOldNotificationJob.perform_later
  end
end

TriggerScheduledItemsJob.prepend_mod_with('TriggerScheduledItemsJob')
