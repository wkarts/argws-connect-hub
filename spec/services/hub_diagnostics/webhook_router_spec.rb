require 'rails_helper'

RSpec.describe HubDiagnostics::WebhookRouter do
  describe '.channel_for_route' do
    it 'normalizes the route phone number without duplicating the plus sign' do
      channel = instance_double(Channel::Whatsapp)

      allow(Channel::Whatsapp).to receive(:find_by)
        .with(phone_number: '5575999999999', provider: 'connectapi')
        .and_return(nil)
      allow(Channel::Whatsapp).to receive(:find_by)
        .with(phone_number: '+5575999999999', provider: 'connectapi')
        .and_return(channel)

      expect(described_class.channel_for_route(phone_number: '5575999999999')).to eq(channel)
    end
  end

  describe '.payload_summary' do
    it 'counts messages and statuses without retaining their content' do
      params = ActionController::Parameters.new(
        entry: [
          { changes: [{ value: { messages: [{ id: 'm1' }, { id: 'm2' }] } }] },
          { changes: [{ value: { statuses: [{ id: 'm1', status: 'delivered' }] } }] }
        ]
      )

      expect(described_class.payload_summary(params)).to eq(
        payload_kind: 'messages_and_statuses',
        entries_count: 2,
        changes_count: 2,
        messages_count: 2,
        statuses_count: 1
      )
    end
  end

  describe '.enqueue' do
    it 'accepts formatted display numbers that normalize to the channel phone' do
      inbox = instance_double(Inbox, id: 3)
      channel = instance_double(
        Channel::Whatsapp,
        id: 2,
        inbox: inbox,
        account_id: 1,
        phone_number: '+5575999999999',
        provider_config: {
          'phone_number_id' => 'phone-id-1',
          'instance_name' => 'hub-instance'
        }
      )
      params = ActionController::Parameters.new(
        phone_number: '5575999999999',
        entry: [{
          changes: [{
            value: {
              metadata: {
                display_phone_number: '+55 (75) 99999-9999',
                phone_number_id: 'phone-id-1'
              },
              messages: [{ id: 'provider-message-1', type: 'text' }]
            }
          }]
        }]
      )

      allow(Webhooks::ConnectApiDiagnosticEventsJob).to receive(:perform_later)
      allow(HubDiagnostics::Recorder).to receive(:emit)

      expect(described_class.enqueue(channel, params)).to eq(:ok)
      expect(Webhooks::ConnectApiDiagnosticEventsJob).to have_received(:perform_later).once
    end
  end
end
