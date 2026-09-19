require 'rails_helper'

RSpec.describe 'Connect|API template HUB variables' do
  let(:remote_template) do
    {
      'id' => 'lt_contact_name',
      'name' => 'hello',
      'language' => 'pt_BR',
      'source' => 'connectapi_local',
      'execution' => 'rendered_text',
      'approved' => true,
      'version' => 1,
      'enabled' => true,
      'available' => true,
      'status' => 'APPROVED',
      'category' => 'OPENING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá! {{1}}' }]
    }
  end

  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      phone_number: '+5575988881111',
      provider_config: {
        'api_key' => 'instance-token',
        'instance_name' => 'liquid-template-instance',
        'phone_number_id' => '5575988881111',
        'business_account_id' => '5575988881111',
        'url' => 'https://connect.example/graph'
      }
    )
  end
  let(:contact) { create(:contact, account: channel.account, name: 'Maria da Silva', phone_number: '+5575999999999') }
  let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox, contact: contact) }
  let(:user) { create(:user, account: channel.account) }

  before do
    entries = channel.opening_template_catalog.reconcile([remote_template])
    channel.update_columns(message_templates: entries)
    allow(GlobalConfigService).to receive(:load).with('CONNECT_API_REQUEST_TIMEOUT', anything).and_return(60)
  end

  it 'resolves contact.name in content and positional parameters before sending to Connect|API' do
    message = Messages::MessageBuilder.new(
      user,
      conversation,
      {
        content: 'Olá! {{contact.name}}',
        message_type: 'outgoing',
        template_params: {
          name: 'hello',
          language: 'pt_BR',
          connect_api_version: 1,
          processed_params: { '1' => '{{contact.name}}' }
        }
      }
    ).perform

    resolved_name = contact.reload.name
    expect(message.content).to eq("Olá! #{resolved_name}")
    expect(message.additional_attributes.dig('template_params', 'processed_params', '1')).to eq(resolved_name)

    request = stub_request(:post, 'https://connect.example/graph/v20.0/5575988881111/messages')
              .with(
                headers: { 'Authorization' => 'Bearer instance-token' },
                body: hash_including(
                  'type' => 'template',
                  'template' => hash_including(
                    'name' => 'hello',
                    'connect_api_version' => 1,
                    'components' => [{
                      'type' => 'body',
                      'parameters' => [{ 'type' => 'text', 'text' => resolved_name }]
                    }]
                  )
                )
              )
              .to_return(
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: { messages: [{ id: 'REAL-LIQUID-MESSAGE-ID' }] }.to_json
              )

    Whatsapp::SendOnWhatsappService.new(message: message).perform

    expect(request).to have_been_requested.once
    expect(message.reload.source_id).to eq('REAL-LIQUID-MESSAGE-ID')
    expect(message.status).not_to eq('failed')
  end

  it 'fails closed before provider delivery when a HUB variable has no value' do
    message = Messages::MessageBuilder.new(
      user,
      conversation,
      {
        content: 'Olá! {{contact.email}}',
        message_type: 'outgoing',
        template_params: {
          name: 'hello',
          language: 'pt_BR',
          connect_api_version: 1,
          processed_params: { '1' => '{{contact.email}}' }
        }
      }
    ).perform

    expect(message.content).to eq('Olá! ')
    expect(message.additional_attributes.dig('template_params', 'processed_params', '1')).to eq('')

    Whatsapp::SendOnWhatsappService.new(message: message).perform

    expect(
      a_request(:post, 'https://connect.example/graph/v20.0/5575988881111/messages')
    ).not_to have_been_made
    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to include('texto não vazio')
  end

end
