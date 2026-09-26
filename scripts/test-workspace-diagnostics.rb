require 'minitest/autorun'
require_relative '../app/services/workspace_apps/frame_policy'
require_relative '../app/services/workspace_apps/destination_probe'

class WorkspaceDiagnosticsTest < Minitest::Test
  def policy(csp: nil, xfo: nil, report: nil, parent: 'https://hub.example.test')
    headers = { 'content-security-policy' => Array(csp), 'x-frame-options' => Array(xfo), 'content-security-policy-report-only' => Array(report) }
    WorkspaceApps::FramePolicy.new(headers: headers, destination: 'https://app.example.test/home', parent: parent).call
  end

  def test_none_and_sameorigin_are_reported_as_blocked
    assert_equal 'blocked', policy(csp: "frame-ancestors 'none'")[:verdict]
    assert_equal 'blocked', policy(xfo: 'SAMEORIGIN')[:verdict]
    assert_equal 'blocked', policy(xfo: 'DENY')[:verdict]
  end

  def test_an_allowed_origin_is_not_a_guarantee_of_browser_compatibility
    assert_equal 'no_block_observed', policy(csp: "default-src 'self'; frame-ancestors 'self' https://hub.example.test")[:verdict]
    assert_equal 'no_block_observed', policy[:verdict]
  end

  def test_enforced_frame_ancestors_supersedes_xfo_but_all_enforced_policies_must_allow
    assert_equal 'no_block_observed', policy(csp: 'frame-ancestors https://hub.example.test', xfo: 'DENY')[:verdict]
    assert_equal 'blocked', policy(csp: ['frame-ancestors https://hub.example.test', "frame-ancestors 'none'"])[:verdict]
    assert_equal 'blocked', policy(csp: "frame-ancestors *, frame-ancestors 'none'")[:verdict]
  end

  def test_report_only_is_not_used_to_block
    result = policy(report: "frame-ancestors 'none'")
    assert_equal 'no_block_observed', result[:verdict]
    assert_equal ["frame-ancestors 'none'"], result[:report_only]
  end

  def test_wildcard_ports_and_self_are_origin_bound
    assert_equal 'no_block_observed', policy(csp: 'frame-ancestors https://*.example.test')[:verdict]
    assert_equal 'blocked', policy(csp: 'frame-ancestors https://*.example.test', parent: 'https://example.test')[:verdict]
    assert_equal 'blocked', policy(csp: 'frame-ancestors https://hub.example.test:8443')[:verdict]
    assert_equal 'no_block_observed', policy(csp: 'frame-ancestors https://hub.example.test:*')[:verdict]
    assert_equal 'blocked', policy(csp: "frame-ancestors 'self'")[:verdict]
    assert_equal 'no_block_observed', policy(csp: "frame-ancestors 'self'", parent: 'https://app.example.test')[:verdict]
    assert_equal 'inconclusive', policy(csp: 'frame-ancestors https://hub.example.test/some/path')[:verdict]
  end

  def test_csp_secure_upgrades_and_case_insensitive_schemes_do_not_report_false_blocks
    %w[http: HTTP: HTTPS: http://hub.example.test HTTP://HUB.EXAMPLE.TEST https://hub.example.test http://hub.example.test:80].each do |source|
      assert_equal 'no_block_observed', policy(csp: "frame-ancestors #{source}")[:verdict], source
    end
    assert_equal 'blocked', policy(csp: 'frame-ancestors https:', parent: 'http://hub.example.test')[:verdict]
    assert_equal 'blocked', policy(csp: 'frame-ancestors http://hub.example.test:8443')[:verdict]
  end

  def test_private_reserved_and_translation_addresses_are_rejected
    %w[127.0.0.1 10.0.0.2 169.254.169.254 172.16.1.2 192.168.0.1 100.64.0.1 198.18.0.1
       0.0.0.0 224.0.0.1 240.0.0.1 192.0.2.1 ::1 ::ffff:127.0.0.1 fc00::1 fe80::1
       64:ff9b::7f00:1 2002:7f00:1::1 2001:db8::1 3fff::1].each do |address|
      refute WorkspaceApps::DestinationProbe.public_address?(address), address
    end
    assert WorkspaceApps::DestinationProbe.public_address?('93.184.216.34')
    assert WorkspaceApps::DestinationProbe.public_address?('2606:4700:4700::1111')
  end

  def probe(url = 'https://app.example.test/home?token=redacted')
    WorkspaceApps::DestinationProbe.new(url: url, hub_origin: 'https://hub.example.test')
  end

  def response(code = '200', headers = {})
    result = Net::HTTPResponse.new('1.1', code, 'Test')
    headers.each { |key, value| result[key] = value }
    result
  end

  def test_private_and_mixed_dns_never_make_an_http_request
    [['127.0.0.1'], ['93.184.216.34', '127.0.0.1']].each do |addresses|
      service = probe
      service.define_singleton_method(:request_head) { |*_args| flunk 'Unexpected network access' }
      Resolv.stub(:getaddresses, addresses) { assert_equal 'blocked_address', service.call[:code] }
    end
  end

  def test_revalidates_every_redirect_and_omits_query_from_diagnostics
    service = probe
    redirect = response('302', 'location' => 'https://internal.example.test/secrets')
    requests = []
    service.define_singleton_method(:request_head) { |uri, address| requests << [uri, address]; redirect }
    resolver = ->(host) { host == 'internal.example.test' ? ['127.0.0.1'] : ['93.184.216.34'] }
    Resolv.stub(:getaddresses, resolver) do
      result = service.call
      assert_equal 'blocked_address', result[:code]
      assert_equal 1, requests.size
      refute_includes result.to_s, 'token='
      refute_includes result.to_s, 'redacted'
    end
  end

  def test_rejects_http_redirects_and_inline_credentials
    %w[http://app.example.test https://user:secret@app.example.test].each do |url|
      assert_equal 'invalid_url', probe(url).call[:code]
    end
  end

  def test_reports_real_dns_timeout_tls_and_connection_errors_without_secret_messages
    { Resolv::ResolvError => 'dns_error', Timeout::Error => 'timeout', OpenSSL::SSL::SSLError => 'tls_error', Errno::ECONNREFUSED => 'connection_refused' }.each do |error, code|
      Resolv.stub(:getaddresses, ->(_host) { raise error, 'do-not-expose-this-detail' }) do
        result = probe.call
        assert_equal code, result[:code]
        refute_includes result.to_s, 'do-not-expose-this-detail'
      end
    end
  end

  def test_request_uses_head_pinned_ip_tls_and_no_forwarded_credentials_or_proxy
    captured = []
    fake = Object.new
    class << fake
      attr_accessor :ipaddr, :use_ssl, :verify_mode, :open_timeout, :read_timeout, :write_timeout, :max_retries
      def start; yield self; end
    end
    ok = response('200', 'x-frame-options' => 'DENY')
    fake.define_singleton_method(:request) { |request| captured << request; ok }
    factory = ->(host, port, proxy) { assert_equal 'app.example.test', host; assert_equal 443, port; assert_nil proxy; fake }
    Resolv.stub(:getaddresses, ['93.184.216.34']) do
      Net::HTTP.stub(:new, factory) do
        result = probe.call
        assert_equal 'blocked', result[:verdict]
        assert_equal 'anonymous_server_head', result[:scope]
      end
    end
    assert_equal '93.184.216.34', fake.ipaddr
    assert_equal OpenSSL::SSL::VERIFY_PEER, fake.verify_mode
    assert_equal 'HEAD', captured.first.method
    %w[authorization cookie referer origin api_access_token access-token].each { |header| assert_nil captured.first[header] }
  end
end
