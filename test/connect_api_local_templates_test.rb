# frozen_string_literal: true

# Standalone regression tests: no Rails boot, database or external delivery.
require 'minitest/autorun'
require 'ostruct'
require_relative '../app/services/connect_api/opening_template_catalog'
require_relative '../app/services/connect_api/local_template_delivery'

class ConnectApiLocalTemplatesTest < Minitest::Test
  def remote(**overrides)
    {
      'name' => 'hello', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'id' => 'local_test', 'origin' => 'CONNECT_LOCAL', 'revision' => 1,
      'status' => 'LOCAL_READY', 'enabled' => true, 'available' => true,
      'meta_approved' => false, 'components' => [{ 'type' => 'BODY', 'text' => 'Olá!' }]
    }.merge(overrides.transform_keys(&:to_s))
  end

  def catalog(templates = [], instance = 'alpha')
    ConnectApi::OpeningTemplateCatalog.new(templates, instance_name: instance)
  end

  def imported(item = remote)
    catalog(catalog.reconcile([item]))
  end

  def fixture_message(text = 'Olá!', params = {})
    OpenStruct.new(content: text, additional_attributes: {
      'template_params' => {
        'name' => 'hello', 'language' => 'pt_BR', 'processed_params' => {},
        'connect_template_id' => 'local_test', 'connect_template_revision' => 1
      }.merge(params)
    })
  end

  def payload(current = imported, msg = fixture_message)
    ConnectApi::LocalTemplateDelivery.new(catalog: current, message: msg,
                                          template_info: { name: 'hello', lang_code: 'pt_BR' }).payload
  end

  def test_local_hello_is_imported_and_enabled_for_opening_without_meta_approval
    template = imported.available_templates(opening_only: true).first
    assert_equal 'hello', template['name']
    assert_equal 'LOCAL_READY', template['status']
    assert_equal false, template['meta_approved']
  end

  def test_resync_preserves_administrative_disable_and_current_revision
    current = imported
    disabled = catalog(current.set_enabled(name: 'hello', language: 'pt_BR', enabled: false))
    updated = catalog(disabled.reconcile([remote(revision: 2)]))
    assert_empty updated.available_templates(opening_only: true)
    assert_equal 2, updated.entries.first['revision']
  end

  def test_empty_catalog_invalidates_old_templates_without_fabricating_hello
    current = catalog(imported.reconcile([]))
    assert_empty current.available_templates
    assert_equal false, current.entries.first['hub_remote_present']
    assert_empty catalog.reconcile([])
  end

  def test_local_disabled_and_deleted_are_not_available
    %w[LOCAL_DISABLED LOCAL_DELETED APPROVED].each do |status|
      assert_empty imported(remote(status: status)).available_templates
    end
    assert_empty imported(remote(enabled: false)).available_templates
    assert_empty imported(remote(available: false)).available_templates
  end

  def test_no_cross_instance_leak
    rows = catalog.reconcile([remote])
    assert_empty catalog(rows, 'beta').available_templates
  end

  def test_invalid_local_identity_or_revision_is_not_imported
    [{ revision: nil }, { revision: '1' }, { revision: 0 }, { id: 'official' }, { meta_approved: true }].each do |changes|
      assert_raises(ConnectApi::OpeningTemplateCatalog::InvalidTemplate) { imported(remote(**changes)) }
    end
  end

  def test_official_approved_template_remains_usable
    item = remote(origin: 'META', status: 'APPROVED', meta_approved: true)
    assert_equal 1, imported(item).available_templates.size
    assert_nil payload(imported(item))
  end

  def test_delivery_includes_current_local_identity_and_revision
    result = payload
    assert_equal 'local_test', result[:connect_template_id]
    assert_equal 1, result[:connect_template_revision]
    assert_equal [], result[:components][0][:parameters]
  end

  def test_stale_revision_and_wrong_id_do_not_send
    [{ 'connect_template_revision' => 0 }, { 'connect_template_revision' => '1' }, { 'connect_template_id' => 'local_other' }].each do |changes|
      assert_raises(ConnectApi::LocalTemplateDelivery::Error) { payload(imported, fixture_message('Olá!', changes)) }
    end
  end

  def test_current_catalog_must_still_allow_the_model
    assert_raises(ConnectApi::LocalTemplateDelivery::Error) { payload(imported(remote(enabled: false))) }
    assert_raises(ConnectApi::LocalTemplateDelivery::Error) { payload(catalog(imported.reconcile([]))) }
  end

  def test_parameters_are_sorted_numerically_not_by_hash_insertion_order
    current = imported(remote(components: [{ 'type' => 'BODY', 'text' => '{{2}} / {{1}} / {{2}}' }]))
    msg = fixture_message('segundo / primeiro / segundo', 'processed_params' => { '2' => 'segundo', '1' => 'primeiro' })
    result = payload(current, msg)
    assert_equal %w[primeiro segundo], result[:components][0][:parameters].map { |param| param[:text] }
  end

  def test_missing_extra_and_blank_parameters_are_rejected
    current = imported(remote(components: [{ 'type' => 'BODY', 'text' => '{{1}}' }]))
    [{}, { '1' => ' ' }, { '1' => 'x', '2' => 'y' }, { '2' => 'x' }].each do |values|
      assert_raises(ConnectApi::LocalTemplateDelivery::Error) { payload(current, fixture_message('x', 'processed_params' => values)) }
    end
  end

  def test_preview_divergence_is_rejected
    assert_raises(ConnectApi::LocalTemplateDelivery::Error) { payload(imported, fixture_message('Outra mensagem')) }
  end

  def test_media_components_are_not_silently_discarded
    current = imported(remote(components: [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Olá!' }]))
    assert_raises(ConnectApi::LocalTemplateDelivery::Error) { payload(current) }
  end
end
