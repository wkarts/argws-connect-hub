require 'rails_helper'

RSpec.describe TriggerScheduledItemsJob do
  subject(:job) { described_class.perform_later }

  let(:account) { create(:account) }

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .on_queue('scheduled_jobs')
  end

  it 'triggers Conversations::ReopenSnoozedConversationsJob' do
    expect(Conversations::ReopenSnoozedConversationsJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'triggers Notification::ReopenSnoozedNotificationsJob' do
    expect(Notification::ReopenSnoozedNotificationsJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'triggers Account::ConversationsResolutionSchedulerJob' do
    expect(Account::ConversationsResolutionSchedulerJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'triggers Channels::Whatsapp::TemplatesSyncSchedulerJob' do
    expect(Channels::Whatsapp::TemplatesSyncSchedulerJob).to receive(:perform_later).once
    described_class.perform_now
  end

  it 'triggers Notification::RemoveOldNotificationJob' do
    expect(Notification::RemoveOldNotificationJob).to receive(:perform_later).once
    described_class.perform_now
  end

  context 'when scheduled campaign jobs are due' do
    let!(:twilio_sms) { create(:channel_twilio_sms) }
    let!(:twilio_inbox) { create(:inbox, channel: twilio_sms) }

    it 'recovers due one-off campaigns through the generic trigger job' do
      campaign = create(:campaign, inbox: twilio_inbox, scheduled_at: 10.days.ago)
      create(:campaign, inbox: twilio_inbox, scheduled_at: 10.days.from_now)

      expect(Campaigns::TriggerCampaignJob).to receive(:perform_later)
        .with(campaign.id, campaign.scheduled_at.iso8601(6)).once

      described_class.perform_now
    end

    it 'recovers due recurring outbound campaigns too' do
      campaign = create(
        :campaign,
        campaign_type: :ongoing,
        inbox: twilio_inbox,
        scheduled_at: 2.minutes.ago,
        trigger_rules: { recurrence: { frequency: 'daily', interval: 1 } }
      )

      expect(Campaigns::TriggerCampaignJob).to receive(:perform_later)
        .with(campaign.id, campaign.scheduled_at.iso8601(6)).once

      described_class.perform_now
    end
  end
end
