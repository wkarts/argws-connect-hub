require 'rails_helper'

RSpec.describe LinkPreviews::Fetcher do
  before do
    Rails.cache.clear
  end

  it 'loads Open Graph metadata from a public HTTP page' do
    allow(Resolv).to receive(:getaddresses) do |host|
      {
        'example.com' => ['93.184.216.34'],
        'cdn.example.com' => ['93.184.216.35']
      }.fetch(host, [])
    end

    stub_request(:get, 'https://example.com/article').to_return(
      status: 200,
      headers: { 'Content-Type' => 'text/html; charset=utf-8' },
      body: <<~HTML
        <html>
          <head>
            <meta property="og:title" content="Título de teste">
            <meta property="og:description" content="Descrição de teste">
            <meta property="og:site_name" content="Example">
            <meta property="og:image" content="https://cdn.example.com/card.jpg">
          </head>
        </html>
      HTML
    )

    preview = described_class.new('https://example.com/article').perform

    expect(preview).to include(
      url: 'https://example.com/article',
      title: 'Título de teste',
      description: 'Descrição de teste',
      site_name: 'Example',
      image_url: 'https://cdn.example.com/card.jpg',
      host: 'example.com'
    )
  end

  it 'rejects localhost and private network targets' do
    expect do
      described_class.new('http://127.0.0.1/admin').perform
    end.to raise_error(described_class::Error)

    allow(Resolv).to receive(:getaddresses)
      .with('internal.example')
      .and_return(['10.10.10.10'])

    expect do
      described_class.new('https://internal.example/').perform
    end.to raise_error(described_class::Error, /rede não permitida/i)
  end

  it 'rejects responses larger than the preview limit' do
    allow(Resolv).to receive(:getaddresses)
      .with('example.com')
      .and_return(['93.184.216.34'])

    stub_request(:get, 'https://example.com/large').to_return(
      status: 200,
      headers: { 'Content-Type' => 'text/html' },
      body: '<html>' + ('x' * (described_class::MAX_BODY_BYTES + 1)) + '</html>'
    )

    expect do
      described_class.new('https://example.com/large').perform
    end.to raise_error(described_class::Error, /excede o limite/i)
  end
end
