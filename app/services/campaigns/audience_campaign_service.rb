# frozen_string_literal: true

class Campaigns::AudienceCampaignService
  pattr_initialize [:campaign!]

  def perform(mark_completed: false)
    raise "Unsupported campaign channel: #{campaign.inbox.channel_type}" unless Campaigns::ChannelDriverResolver.supported?(campaign.inbox)

    driver = Campaigns::ChannelDriverResolver.resolve(campaign)
    campaign.completed! if mark_completed

    audience_contacts.find_each do |contact|
      next unless driver.deliverable?(contact)

      driver.deliver(contact)
    end
  end

  private

  def audience_contacts
    audience_label_ids = Array(campaign.audience).select { |item| item['type'] == 'Label' }.pluck('id')
    audience_labels = campaign.account.labels.where(id: audience_label_ids).pluck(:title)

    campaign.account.contacts.tagged_with(audience_labels, any: true)
  end
end
