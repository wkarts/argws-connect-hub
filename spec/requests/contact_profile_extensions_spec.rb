require 'rails_helper'

RSpec.describe 'Contact profile extensions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }

  it 'stores and returns date of birth' do
    patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          headers: admin.create_new_auth_token,
          params: { date_of_birth: '1990-05-20' },
          as: :json

    expect(response).to have_http_status(:success)
    expect(contact.reload.date_of_birth).to eq(Date.new(1990, 5, 20))

    get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('payload', 'date_of_birth')).to eq('1990-05-20')
  end

  it 'rejects a future date of birth' do
    patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}",
          headers: admin.create_new_auth_token,
          params: { date_of_birth: 1.day.from_now.to_date.iso8601 },
          as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(contact.reload.date_of_birth).to be_nil
  end
end
