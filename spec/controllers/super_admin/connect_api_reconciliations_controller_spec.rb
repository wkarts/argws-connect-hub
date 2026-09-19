require 'rails_helper'

RSpec.describe 'Super Admin Connect API reconciliation', type: :request do
  let(:super_admin) { create(:super_admin) }
  let!(:channel) do
    create(
      :channel_whatsapp,
      provider: 'connectapi',
      sync_templates: false,
      validate_provider_config: false,
      provider_config: {
        'instance_name' => 'admin-history-instance',
        'api_key' => 'instance-token'
      }
    )
  end

  before do
    sign_in(super_admin, scope: :super_admin)
  end

  it 'enqueues a date range reconciliation in Bahia timezone' do
    expect do
      post super_admin_connect_api_reconciliation_path, params: {
        channel_id: channel.id,
        from_at: '2026-09-18T08:00',
        to_at: '2026-09-18T18:30'
      }
    end.to have_enqueued_job(Channels::Whatsapp::ConnectApiHistoricalReconciliationJob)

    expect(response).to redirect_to(
      super_admin_connect_api_reconciliation_path(channel_id: channel.id)
    )

    operation = channel.reload.provider_config['hub_reconciliation_operation']
    expect(operation['mode']).to eq('range')
    expect(operation['state']).to eq('queued')
    expect(Time.iso8601(operation['from_at']).utc_offset).to eq(0)
    expect(Time.iso8601(operation['to_at'])).to be > Time.iso8601(operation['from_at'])
  end

  it 'enqueues an import of all history available in Connect API' do
    expect do
      post import_all_super_admin_connect_api_reconciliation_path,
           params: { channel_id: channel.id }
    end.to have_enqueued_job(Channels::Whatsapp::ConnectApiHistoricalReconciliationJob)

    expect(response).to redirect_to(
      super_admin_connect_api_reconciliation_path(channel_id: channel.id)
    )

    operation = channel.reload.provider_config['hub_reconciliation_operation']
    expect(operation['mode']).to eq('all')
    expect(operation['state']).to eq('queued')
  end

  it 'does not enqueue a second operation while one is active' do
    config = channel.provider_config.to_h.deep_dup
    config['hub_reconciliation_operation'] = {
      'operation_id' => SecureRandom.uuid,
      'state' => 'running',
      'mode' => 'all'
    }
    channel.update_columns(provider_config: config)

    expect do
      post import_all_super_admin_connect_api_reconciliation_path,
           params: { channel_id: channel.id }
    end.not_to have_enqueued_job(Channels::Whatsapp::ConnectApiHistoricalReconciliationJob)

    expect(response).to have_http_status(:found)
    expect(flash[:alert]).to include('Já existe uma reconciliação em andamento')
  end
end
