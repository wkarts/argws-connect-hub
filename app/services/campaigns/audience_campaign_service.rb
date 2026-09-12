# frozen_string_literal: true

class Campaigns::AudienceCampaignService
  class DeliveryError < StandardError; end

  pattr_initialize [:campaign!]

  def perform(mark_completed: false)
    raise "Unsupported campaign channel: #{campaign.inbox.channel_type}" unless Campaigns::ChannelDriverResolver.supported?(campaign.inbox)

    driver = Campaigns::ChannelDriverResolver.resolve(campaign)
    stats = { matched: 0, eligible: 0, delivered: 0, failed: 0 }

    audience_contacts.find_each do |contact|
      stats[:matched] += 1
      next unless driver.deliverable?(contact)

      stats[:eligible] += 1
      begin
        driver.deliver(contact)
        stats[:delivered] += 1
      rescue StandardError => e
        stats[:failed] += 1
        Rails.logger.error(
          "Campaign #{campaign.id} failed for contact #{contact.id}: #{e.class}: #{e.message}"
        )
      end
    end

    if stats[:eligible].positive? && stats[:delivered].zero? && stats[:failed].positive?
      raise DeliveryError, "Campaign #{campaign.id} could not dispatch any eligible delivery"
    end

    campaign.completed! if mark_completed
    stats
  end

  private

  def audience_contacts
    audience_label_ids = Array(campaign.audience).select { |item| item['type'] == 'Label' }.pluck('id')
    audience_labels = campaign.account.labels.where(id: audience_label_ids).pluck(:title)

    campaign.account.contacts.tagged_with(audience_labels, any: true)
  end
end
