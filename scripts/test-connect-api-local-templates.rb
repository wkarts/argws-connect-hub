# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'ostruct'
require 'logger'
require 'timeout'
require_relative '../app/services/connect_api/opening_template_catalog'

class Object
  def blank?; respond_to?(:empty?) ? empty? : !self; end
  def present?; !blank?; end
  def presence; self if present?; end
end
class GlobalConfigService
  def self.load(key, fallback)
    raise 'global credential must never be read for template delivery' if key == 'CONNECT_API_AUTH_TOKEN'
    fallback
  end
end
module Rails
  def self.logger; @logger ||= Logger.new(File::NULL); end
end
module Whatsapp
  module Providers
    class WhatsappCloudService
      attr_accessor :whatsapp_channel
      def send_template(*); :official_path; end
      def phone_id_path; 'https://api.invalid/graph/v20.0/5511999999999'; end
    end
  end
end
module HTTParty
  class << self
    attr_accessor :calls, :response, :exception
    def post(url, **options)
      self.calls ||= []
      calls << [url, options]
      raise exception if exception
      response
    end
  end
end
require_relative '../app/services/whatsapp/providers/connect_api_service'

class ConnectApiLocalTemplatesTest < Minitest::Test
  Local = ConnectApi::LocalTemplateMessage
  Catalog = ConnectApi::OpeningTemplateCatalog

  def remote(name = 'hello', **extra)
    {
      'id' => 'lt_fixture', 'name' => name, 'language' => 'pt_BR',
      'source' => 'connectapi_local', 'execution' => 'rendered_text',
      'approved' => true, 'status' => 'APPROVED', 'category' => 'OPENING', 'version' => 1,
      'enabled' => true, 'available' => true,
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá! Como podemos ajudar?' }]
    }.merge(extra.transform_keys(&:to_s))
  end

  def params(template = remote, values = {})
    { 'name' => template['name'], 'language' => template['language'], 'connect_api_version' => template['version'], 'processed_params' => values }
  end

  def catalog(entries = [], instance = 'a')
    Catalog.new(entries, instance_name: instance)
  end

  def test_imports_real_approved_hello
    entries = catalog.reconcile([remote, remote('notice')])
    assert_equal [true, false], entries.map { |item| item['hub_opening_enabled'] }
    assert_equal 'APPROVED', entries[0]['status']
    assert_equal true, entries[0]['approved']
    assert_equal 'OPENING', entries[0]['category']
    assert_equal [entries[0]], catalog(entries).available_templates(opening_only: true)
  end

  def test_template_status_requires_approved_contract_and_provenance
    %w[source status execution approved enabled available version].each do |field|
      invalid = remote.reject { |key, _| key == field }
      refute Local.available?(invalid), field
    end
    refute Local.available?(remote(approved: false))
    refute Local.available?(remote(status: 'PENDING'))
    refute Local.available?(remote(version: '1'))
  end

  def test_official_eligibility_stays_unchanged
    official = remote.reject { |key, _| %w[source execution approved version].include?(key) }.merge('status' => 'APPROVED')
    assert catalog(catalog.reconcile([official])).available_templates.any?
    refute catalog(catalog.reconcile([official.merge('status' => 'PENDING')])).available_templates.any?
  end

  def test_choices_survive_revision_disable_removal_and_return
    entries = catalog.reconcile([remote, remote('notice')])
    entries = catalog(entries).set_enabled(name: 'hello', language: 'pt_BR', enabled: false)
    entries = catalog(entries).set_enabled(name: 'notice', language: 'pt_BR', enabled: true)
    entries = catalog(entries).reconcile([remote(version: 2), remote('notice', enabled: false, available: false)])
    assert_empty catalog(entries).available_templates(opening_only: true)
    entries = catalog(entries).reconcile([])
    assert_empty catalog(entries).available_templates
    entries = catalog(entries).reconcile([remote(version: 4), remote('notice', version: 4)])
    assert_equal ['notice'], catalog(entries).available_templates(opening_only: true).map { |item| item['name'] }
  end

  def test_no_cross_instance_or_language_choice_leak
    entries = catalog.reconcile([remote, remote(language: 'en_US')])
    entries = catalog(entries).set_enabled(name: 'hello', language: 'en_US', enabled: false)
    assert_equal ['pt_BR'], catalog(entries).available_templates(opening_only: true).map { |item| item['language'] }
    assert_empty catalog(entries, 'b').available_templates
    assert_empty catalog.reconcile([])
  end

  def test_zero_variables_build_empty_array_and_exact_persisted_preview
    local = Local.new(remote, params)
    assert_equal 'Olá! Como podemos ajudar?', local.rendered_text
    assert_equal [], local.payload[:components][0][:parameters]
    assert_equal 1, local.payload[:connect_api_version]
    assert local.validate_content!('Olá! Como podemos ajudar?').nil?
    assert_raises(Local::Error) { local.validate_content!('caller changed arbitrary text') }
  end

  def test_static_header_footer_and_single_pass_literal_substitution
    template = remote(components: [{ 'type' => 'FOOTER', 'text' => 'Equipe' }, { 'type' => 'BODY', 'text' => 'Olá {{1}}: {{2}} / {{1}}' }, { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Suporte' }])
    local = Local.new(template, params(template, { '2' => '$&', '1' => '{{2}}' }))
    assert_equal 'Suporte' + "\n\nOlá {{2}}: $& / {{2}}\n\nEquipe", local.rendered_text
  end

  def test_ten_variables_use_numeric_order_not_insertion_order
    template = remote(components: [{ 'type' => 'BODY', 'text' => (1..10).map { |i| "{{#{i}}}" }.join('/') }])
    values = (1..10).to_a.reverse.to_h { |i| [i.to_s, i.to_s] }
    local = Local.new(template, params(template, values))
    assert_equal (1..10).map(&:to_s), local.payload[:components].first[:parameters].map { |item| item[:text] }
  end

  def test_missing_extra_invalid_variables_and_stale_version_fail
    template = remote(components: [{ 'type' => 'BODY', 'text' => '{{1}}' }])
    [{}, { '1' => '' }, { '1' => 1 }, { '1' => 'a', '2' => 'b' }, { '1' => 'a' * 1025 }, { '1' => "\0" }].each do |values|
      assert_raises(Local::Error) { Local.new(template, params(template, values)).rendered_text }
    end
    assert_raises(Local::Error) { Local.new(remote(version: 2), params).rendered_text }
    assert_raises(Local::Error) { Local.new(remote, params.merge('name' => 'other')).rendered_text }
  end

  def test_malformed_definition_and_media_are_rejected
    [[], [{ 'type' => 'BUTTONS', 'text' => 'a' }], [{ 'type' => 'BODY', 'text' => '{{99999999}}' }], [{ 'type' => 'BODY', 'text' => '{{2}}' }], [{ 'type' => 'BODY', 'format' => 'IMAGE', 'text' => 'a' }]].each do |components|
      assert_raises(Local::Error) { Local.new(remote(components: components), params).rendered_text }
    end
  end

  def setup_sender(template = remote)
    entries = catalog.reconcile([template])
    sender = Whatsapp::Providers::ConnectApiService.new
    sender.whatsapp_channel = OpenStruct.new(provider_config: { 'api_key' => 'instance-token-only' }, opening_template_catalog: catalog(entries))
    message = OpenStruct.new(content: 'Olá! Como podemos ajudar?', additional_attributes: { 'template_params' => params(template) }, content_attributes: {})
    def message.update!(attributes); attributes.each { |key, value| self[key] = value }; end
    HTTParty.calls = []; HTTParty.exception = nil
    HTTParty.response = OpenStruct.new(success?: true, code: 200, parsed_response: { 'messages' => [{ 'id' => 'REAL_ID' }] })
    [sender, message]
  end

  def test_real_provider_override_uses_instance_bearer_version_and_exactly_one_graph_send
    sender, message = setup_sender
    id = sender.send_template(message, '5511999999999', { name: 'hello', lang_code: 'pt_BR', parameters: nil })
    assert_equal 'REAL_ID', id
    assert_equal 'REAL_ID', message.source_id
    assert_equal 1, HTTParty.calls.size
    options = HTTParty.calls[0][1]
    assert_equal 'Bearer instance-token-only', options[:headers]['Authorization']
    refute options[:headers].key?('apikey')
    assert_equal false, options[:follow_redirects]
    data = JSON.parse(options[:body])
    assert_equal 'template', data['type']
    assert_equal [], data['template']['components'][0]['parameters']
    assert_equal 1, data['template']['connect_api_version']
    refute data.key?('text')
    assert_equal true, message.content_attributes['connect_api_template']['approved']
    assert_equal 'APPROVED', message.content_attributes['connect_api_template']['status']
  end

  def test_empty_instance_token_does_not_fall_back_to_global_or_send
    sender, message = setup_sender
    sender.whatsapp_channel.provider_config['api_key'] = ''
    assert_nil sender.send_template(message, '5511999999999', { name: 'hello', lang_code: 'pt_BR' })
    assert_empty HTTParty.calls
    assert_equal :failed, message.status
  end

  def test_network_error_is_not_retried_as_text_or_other_credentials
    sender, message = setup_sender
    HTTParty.exception = Timeout::Error.new('simulated only')
    assert_nil sender.send_template(message, '5511999999999', { name: 'hello', lang_code: 'pt_BR' })
    assert_equal 1, HTTParty.calls.size
    assert_equal :failed, message.status
  end

  def test_http_error_and_missing_real_id_are_not_reported_as_success
    sender, message = setup_sender
    HTTParty.response = OpenStruct.new(success?: false, code: 409)
    assert_nil sender.send_template(message, '5511999999999', { name: 'hello', lang_code: 'pt_BR' })
    assert_equal :failed, message.status
    sender, message = setup_sender
    HTTParty.response = OpenStruct.new(success?: true, code: 200, parsed_response: { 'messages' => [] })
    assert_nil sender.send_template(message, '5511999999999', { name: 'hello', lang_code: 'pt_BR' })
    assert_nil message.source_id
  end

  def test_official_delivery_still_uses_the_existing_parent_method
    sender, message = setup_sender(remote(source: 'meta', status: 'APPROVED'))
    assert_equal :official_path, sender.send_template(message, '5511999999999', { name: 'hello', lang_code: 'pt_BR' })
    assert_empty HTTParty.calls
  end
end
