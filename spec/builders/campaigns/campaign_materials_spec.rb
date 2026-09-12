# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Campaign materials delivery' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, identifier: 'campaign-material-contact') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:campaign) do
    create(
      :campaign,
      account: account,
      inbox: inbox,
      trigger_rules: { url: 'https://test.com' }
    )
  end

  it 'copies HTML and JPEG materials to the outgoing campaign message' do
    html_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('<html><body>Campanha</body></html>'),
      filename: 'campanha.html',
      content_type: 'text/html'
    )
    jpeg_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('jpeg-binary-placeholder'),
      filename: 'campanha.jpg',
      content_type: 'image/jpeg'
    )
    campaign.materials.attach([html_blob, jpeg_blob])

    conversation = Campaigns::CampaignConversationBuilder.new(
      contact_inbox_id: contact_inbox.id,
      campaign_display_id: campaign.display_id
    ).perform

    expect(conversation).to be_present
    files = conversation.messages.first.attachments.map(&:file)
    expect(files.map { |file| file.filename.to_s }).to contain_exactly('campanha.html', 'campanha.jpg')
    expect(files.map(&:content_type)).to contain_exactly('text/html', 'image/jpeg')
  end
end
