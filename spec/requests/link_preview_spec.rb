require 'rails_helper'

RSpec.describe 'Link preview', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:preview) do
    {
      url: 'https://example.com/',
      title: 'Example',
      description: 'Preview',
      host: 'example.com'
    }
  end

  it 'returns a signed preview for an authenticated account user' do
    fetcher = instance_double(LinkPreviews::Fetcher, perform: preview)
    allow(LinkPreviews::Fetcher).to receive(:new)
      .with('https://example.com/')
      .and_return(fetcher)
    allow(LinkPreviews::Token).to receive(:issue)
      .with(preview)
      .and_return('signed-preview-token')

    get "/api/v1/accounts/#{account.id}/link_preview",
        headers: admin.create_new_auth_token,
        params: { url: 'https://example.com/' },
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['preview']).to eq(preview.deep_stringify_keys)
    expect(response.parsed_body['preview_token']).to eq('signed-preview-token')
  end

  it 'does not expose fetch errors to the composer' do
    allow_any_instance_of(LinkPreviews::Fetcher)
      .to receive(:perform)
      .and_raise(LinkPreviews::Fetcher::Error, 'URL inválida.')

    get "/api/v1/accounts/#{account.id}/link_preview",
        headers: admin.create_new_auth_token,
        params: { url: 'http://127.0.0.1/' },
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['preview']).to be_nil
  end
end
