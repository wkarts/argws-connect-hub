# frozen_string_literal: true

class Campaigns::OneoffCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" unless valid_campaign?
    raise 'Completed Campaign' if campaign.completed?

    driver = Campaigns::ChannelDriverResolver.resolve(campaign)

    # Preserve current one-off semantics: mark completed before iterating so
    # concurrent scheduler jobs cannot dispatch the same campaign twice.
    campaign.completed!

    audience_contacts.find_each do |contact|
      next unless driver.deliverable?(contact)

      driver.deliver(contact)
    end
  end

  private

  def valid_campaign?
    campaign.one_off? && Campaigns::ChannelDriverResolver.supported?(campaign.inbox)
  end

  def audience_contacts
    audience_label_ids = Array(campaign.audience).select { |item| item['type'] == 'Label' }.pluck('id')
    audience_labels = campaign.account.labels.where(id: audience_label_ids).pluck(:title)

    campaign.account.contacts.tagged_with(audience_labels, any: true)
  end
end
