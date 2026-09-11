# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../app/services/connect_api/opening_template_catalog'

class OpeningTemplateCatalogTest < Minitest::Test
  Catalog = ConnectApi::OpeningTemplateCatalog

  def remote(name = 'hello', language = 'pt_BR', **attributes)
    {
      'id' => "remote-#{name}-#{language}", 'name' => name, 'language' => language,
      'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => "Remote content for #{name}" }]
    }.merge(attributes.transform_keys(&:to_s))
  end

  def catalog(templates = [], instance = 'instance-a')
    Catalog.new(templates, instance_name: instance)
  end

  def test_imports_remote_content_verbatim_and_enables_only_exact_hello
    input = [remote, remote('Hello'), remote('hello_world'), remote('notice')]
    result = catalog.reconcile(input)
    assert_equal [true, false, false, false], result.map { |t| t['hub_opening_enabled'] }
    assert_equal input.map { |t| t['components'] }, result.map { |t| t['components'] }
    refute input.first.key?('hub_opening_enabled')
  end

  def test_never_synthesizes_hello_or_other_templates
    assert_empty catalog.reconcile([])
    assert_equal ['notice'], catalog.reconcile([remote('notice')]).map { |t| t['name'] }
  end

  def test_preserves_disable_hello_and_enable_other_choices
    entries = catalog.reconcile([remote, remote('notice')])
    entries = catalog(entries).set_enabled(name: 'hello', language: 'pt_BR', enabled: false)
    entries = catalog(entries).set_enabled(name: 'notice', language: 'pt_BR', enabled: true)
    result = catalog(entries).reconcile([remote, remote('notice'), remote('new')])
    assert_equal [false, true, false], result.map { |t| t['hub_opening_enabled'] }
  end

  def test_disappeared_templates_keep_choices_but_cannot_be_used
    entries = catalog.reconcile([remote])
    result = catalog(entries).reconcile([])
    assert result.first['hub_opening_enabled']
    refute result.first['hub_remote_present']
    assert_empty catalog(result).available_templates(opening_only: true)
    result = catalog(result).reconcile([remote])
    assert_equal ['hello'], catalog(result).available_templates(opening_only: true).map { |t| t['name'] }
  end

  def test_disabled_choice_survives_disappearance_and_remote_id_change
    entries = catalog.reconcile([remote])
    entries = catalog(entries).set_enabled(name: 'hello', language: 'pt_BR', enabled: false)
    missing = catalog(entries).reconcile([])
    result = catalog(missing).reconcile([remote(id: 'new-remote-id')])
    assert_equal 'new-remote-id', result.first['id']
    refute result.first['hub_opening_enabled']
  end

  def test_rejected_pending_paused_and_disabled_are_unavailable
    %w[REJECTED PENDING PAUSED DISABLED DELETED UNKNOWN].each do |status|
      result = catalog.reconcile([remote(status: status)])
      assert result.first['hub_opening_enabled']
      assert_empty catalog(result).available_templates, status
    end
  end

  def test_approved_status_is_case_insensitive_and_missing_status_is_not_fabricated
    assert catalog.reconcile([remote(status: 'approved')]).first['hub_remote_available']
    template = remote.reject { |key, _| key == 'status' }
    result = catalog.reconcile([template])
    assert result.first['hub_remote_available']
    refute result.first.key?('status')
  end

  def test_remote_unavailability_overrides_the_local_choice
    [false, 0, 'false', '0'].each do |value|
      %w[available enabled].each do |key|
        result = catalog.reconcile([remote(**{ key => value })])
        assert_empty catalog(result).available_templates
      end
    end
  end

  def test_languages_are_independent
    entries = catalog.reconcile([remote, remote('hello', 'en_US')])
    entries = catalog(entries).set_enabled(name: 'hello', language: 'en_US', enabled: false)
    assert_equal ['pt_BR'], catalog(entries).available_templates(opening_only: true).map { |t| t['language'] }
  end

  def test_instances_and_inboxes_do_not_share_choices
    first = catalog.reconcile([remote, remote('notice')])
    first = catalog(first).set_enabled(name: 'notice', language: 'pt_BR', enabled: true)
    assert_empty catalog(first, 'instance-b').available_templates(opening_only: true)
    second = catalog(first, 'instance-b').reconcile([remote('notice')])
    refute catalog(second, 'instance-b').entries.first['hub_opening_enabled']
    assert catalog(second).available_templates(opening_only: true).any? { |t| t['name'] == 'notice' }
  end

  def test_legacy_or_unverified_templates_are_not_offered_or_retained_as_remote_records
    assert_empty catalog([remote]).available_templates
    assert_empty catalog([remote]).reconcile([])
    assert_raises(Catalog::TemplateNotFound) do
      catalog([remote]).set_enabled(name: 'hello', language: 'pt_BR', enabled: true)
    end
  end

  def test_remote_payload_cannot_override_administrative_flags
    result = catalog.reconcile([remote('notice', hub_opening_enabled: true, hub_instance_name: 'other')])
    refute result.first['hub_opening_enabled']
    assert_equal 'instance-a', result.first['hub_instance_name']
  end

  def test_invalid_response_is_rejected_instead_of_being_imported_as_empty
    [nil, {}, 'oops', [nil], [{ 'name' => 'hello' }], [remote(components: nil)]].each do |input|
      assert_raises(Catalog::InvalidTemplate) { catalog.reconcile(input) }
    end
  end

  def test_invalid_toggle_and_unknown_template_are_rejected
    entries = catalog.reconcile([remote])
    [nil, '', 'false', 'true', 0, 1].each do |enabled|
      assert_raises(ArgumentError) { catalog(entries).set_enabled(name: 'hello', language: 'pt_BR', enabled: enabled) }
    end
    assert_raises(Catalog::TemplateNotFound) do
      catalog(entries).set_enabled(name: 'other', language: 'pt_BR', enabled: true)
    end
  end

  def test_reply_catalog_can_include_a_disabled_opening_template
    entries = catalog.reconcile([remote('notice')])
    assert_equal 1, catalog(entries).available_templates.size
    assert_empty catalog(entries).available_templates(opening_only: true)
  end

  def test_a_status_change_updates_availability_without_overwriting_the_preference
    entries = catalog.reconcile([remote])
    paused = catalog(entries).reconcile([remote(status: 'PAUSED')])
    assert_empty catalog(paused).available_templates(opening_only: true)
    approved = catalog(paused).reconcile([remote])
    assert_equal 1, catalog(approved).available_templates(opening_only: true).size
  end
end
