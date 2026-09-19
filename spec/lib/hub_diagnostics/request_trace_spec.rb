require 'rails_helper'

RSpec.describe HubDiagnostics::RequestTrace do
  let(:env) do
    {
      'REQUEST_METHOD' => 'POST',
      'action_dispatch.request_id' => 'request-1',
      'action_dispatch.request.path_parameters' => {
        controller: 'webhooks/whatsapp',
        action: 'process_payload'
      }
    }
  end

  it 'returns the application response even when diagnostic recording fails' do
    app = ->(_request_env) { [200, { 'Content-Type' => 'text/plain' }, ['ok']] }
    allow(HubDiagnostics::Recorder).to receive(:emit).and_raise(IOError, 'diagnostic disk unavailable')

    status, headers, body = described_class.new(app).call(env)

    expect(status).to eq(200)
    expect(headers['Content-Type']).to eq('text/plain')
    expect(body).to eq(['ok'])
  end

  it 're-raises only the original application failure when diagnostic error recording also fails' do
    application_error = Class.new(StandardError)
    calls = 0
    app = lambda do |_request_env|
      calls += 1
      raise application_error, 'application failed'
    end
    allow(HubDiagnostics::Recorder).to receive(:error).and_raise(IOError, 'diagnostic disk unavailable')

    expect do
      described_class.new(app).call(env)
    end.to raise_error(application_error, 'application failed')

    expect(calls).to eq(1)
  end
end
