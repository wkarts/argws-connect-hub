# Standalone behavioral tests against the actual group service/controller code.
# In-memory collaborators replace Rails, ActiveRecord, storage and HTTP. These
# tests do NOT validate SQL, callbacks, transactions, auth middleware or workers.
abort 'Run standalone, not inside a Rails application' if defined?(Rails)
require 'minitest/autorun'
require 'json'
require 'ostruct'
require 'securerandom'

class Object
  def blank? = respond_to?(:empty?) ? !!empty? : !self
  def present? = !blank?
  def presence = present? ? self : nil
end
class String
  def blank? = strip.empty?
  def first(n) = self[0, n]
end
class Numeric
  def seconds = self
end
class Time
  def self.current = now
end
class Hash
  def with_indifferent_access = TestIndifferentHash.new(self)
  def deep_stringify_keys
    transform_keys(&:to_s).transform_values do |value|
      value.is_a?(Hash) ? value.deep_stringify_keys : value.is_a?(Array) ? value.map { |item| item.is_a?(Hash) ? item.deep_stringify_keys : item } : value
    end
  end
end
class TestIndifferentHash < Hash
  def initialize(value)
    super()
    value.each { |k, v| self[k.to_s] = wrap(v) }
  end
  def [](key) = super(key.is_a?(Symbol) ? key.to_s : key)
  def []=(key, value)
    super(key.is_a?(Symbol) ? key.to_s : key, value)
  end
  def dig(key, *path)
    value = self[key]
    path.empty? || value.nil? ? value : value.dig(*path)
  end
  def wrap(value)
    value.is_a?(Hash) ? self.class.new(value) : value.is_a?(Array) ? value.map { |item| wrap(item) } : value
  end
end
module ActiveModel
  module Type
    class Boolean
      def cast(value) = [true, 1, '1', 'true'].include?(value)
    end
  end
end
module HubDiagnostics
  class SourceMessagePending < StandardError; end
  class BindingBusy < StandardError; end
end
module ConnectApi
  class Error < StandardError; end
end
module Whatsapp
  module Groups
    module Lock
      def self.with(_group) = yield
    end
    class BroadcastJob
      def self.perform_later(*) = nil
    end
    class MediaJob
      def self.perform_later(*) = nil
    end
  end
end
module Api
  module V1; end
end
module AccessTokenAuthHelper; end
class ApplicationController
  def self.before_action(*) = nil
  attr_accessor :params, :request, :response, :sent_data, :head_status
  def initialize
    @params = {}; @request = OpenStruct.new(headers: {}); @response = OpenStruct.new(headers: {})
  end
  def send_data(data, **options) = @sent_data = [data, options]
  def head(status) = @head_status = status
end

class TestRecord < OpenStruct
  class << self
    def records = (@records ||= [])
    def reset = @records = []
    def where(*args) = TestRelation.new(records).where(*args)
    def joins(*) = TestRelation.new(records)
    def find_by(**criteria) = where(criteria).first
  end
end
class TestRelation
  include Enumerable
  def initialize(rows, factory = nil)
    @rows = rows; @factory = factory
  end
  def each(&block) = @rows.each(&block)
  def where(criteria, *)
    if !criteria.is_a?(Hash)
      raise 'SQL is not evaluated by these isolated tests' unless @rows.empty?
      return self
    end
    TestRelation.new(@rows.select { |row| matches?(row, criteria) }, @factory)
  end
  def matches?(row, criteria)
    criteria.all? do |key, expected|
      actual = key == :whatsapp_groups ? row.whatsapp_group : row.public_send(key)
      expected.is_a?(Hash) ? matches?(actual, expected) : expected.is_a?(Array) ? expected.include?(actual) : actual == expected
    end
  end
  def joins(*) = self
  def select(field = nil, &block) = field ? @rows.map { |row| row.public_send(field) } : @rows.select(&block)
  def limit(value) = TestRelation.new(@rows.take(value), @factory)
  def first = @rows.first
  def to_a = @rows.dup
  def size = @rows.size
  def exists?(criteria = nil) = criteria ? where(criteria).any? : any?
  def find_by(**criteria) = where(criteria).first
  def find_by!(**criteria) = find_by(**criteria) || raise('Not found')
  def find_or_create_by!(**criteria)
    found = find_by(**criteria)
    return found if found
    record = TestRecord.new(criteria); yield record; @rows << record; record
  end
  def create!(attributes = {}, **keywords)
    attributes = attributes.merge(keywords)
    raise 'Factory required' unless @factory
    record = @factory.call(attributes); @rows << record; record
  end
end
class Message < TestRecord; end
class ContactInbox < TestRecord; end
class Attachment < TestRecord; end
module Channel
  class Whatsapp < TestRecord; end
end
class TestFiles < Array
  attr_reader :purged
  def attached? = any?
  def purge_later = @purged = true
end
class WhatsappGroupMessage < TestRecord
  MAX_FILE_BYTES = 25 * 1024 * 1024
  def initialize(attributes = {})
    super({ id: rand(1..100_000), deleted_at: nil, status: 'received', files: TestFiles.new,
            external_error: nil, outgoing?: false }.merge(attributes))
  end
  def with_lock = yield
  def update!(**attributes) = attributes.each { |key, value| self[key] = value }
end
class WhatsappGroup < TestRecord
  JID_PATTERN = /\A\d+(?:-\d+)?@g\.us\z/
  def management? = treatment == 'management'
  def active? = enabled
  def transaction = yield
  def update_columns(attributes = {}, **keywords) = attributes.merge(keywords).each { |key, value| self[key] = value }
end
module ActiveStorage
  class Blob < TestRecord; end
end

root = File.expand_path('..', __dir__)
%w[status incoming provider router storage_guard].each { |file| require File.join(root, "app/services/whatsapp/groups/#{file}") }
require File.join(root, 'app/controllers/api/v1/group_files_controller')

class IsolatedGroupRuntimeTest < Minitest::Test
  JID = '120363000000001@g.us'
  def setup
    [Message, ContactInbox, Attachment, Channel::Whatsapp, WhatsappGroup, WhatsappGroupMessage, ActiveStorage::Blob].each(&:reset)
    @inbox = OpenStruct.new(id: 7, account_id: 1,
      channel: OpenStruct.new(provider_config: { 'instance_name' => 'inbox-group' }))
    @group = WhatsappGroup.new(id: 1, inbox: @inbox, account_id: 1, inbox_id: 7, jid: JID, name: 'Gerencial', treatment: 'management',
      enabled: true, policy_version: 1, mode_changed_at: nil, last_activity_at: nil)
    managed = []
    @group.whatsapp_group_messages = TestRelation.new(managed, ->(attrs) { WhatsappGroupMessage.new(attrs.merge(whatsapp_group: @group)) })
    @group.whatsapp_group_deliveries = TestRelation.new([], ->(attrs) { TestRecord.new(attrs) })
    @group.whatsapp_group_pending_events = TestRelation.new([])
    @group.conversations = TestRelation.new([])
    WhatsappGroup.records << @group
  end

  def test_status_advances_but_does_not_regress_after_read
    record = WhatsappGroupMessage.new(status: 'sent')
    %w[delivered read delivered sent failed].each { |value| Whatsapp::Groups::Status.apply!(record, value) }
    assert_equal 'read', record.status
    assert_nil record.external_error
  end
  def test_revoke_removes_content_and_never_resurrects
    record = WhatsappGroupMessage.new(content: 'private')
    timestamp = Time.utc(2026, 9, 26)
    Whatsapp::Groups::Status.apply!(record, 'deleted', timestamp)
    assert_equal timestamp, record.deleted_at
    assert_nil record.content
    assert record.files.purged
    Whatsapp::Groups::Status.apply!(record, 'read')
    assert_equal 'received', record.status
  end
  def seed_receipt(group = @group)
    record = WhatsappGroupMessage.new(whatsapp_group: group, source_id: 'SAME-ID', status: 'sent')
    WhatsappGroupMessage.records << record
    record
  end
  def test_receipt_for_individual_does_not_change_group_with_same_id
    record = seed_receipt
    result = Whatsapp::Groups::Status.consume(@inbox, { id: 'SAME-ID', status: 'read', recipient_id: '55119999@s.whatsapp.net' })
    assert_equal false, result
    assert_equal 'sent', record.status
  end
  def test_receipt_without_peer_and_with_legacy_collision_is_rejected
    record = seed_receipt
    Message.records << Message.new(account_id: 1, inbox_id: 7, source_id: 'SAME-ID')
    assert_raises(HubDiagnostics::SourceMessagePending) { Whatsapp::Groups::Status.consume(@inbox, { id: 'SAME-ID', status: 'read' }) }
    assert_equal 'sent', record.status
  end
  def test_receipt_with_explicit_group_id_updates_only_that_group
    record = seed_receipt
    other = seed_receipt(WhatsappGroup.new(id: 2, account_id: 1, inbox_id: 7, jid: '120363000000002@g.us'))
    assert Whatsapp::Groups::Status.consume(@inbox, { id: 'SAME-ID', status: 'read', recipient_id: JID })
    assert_equal 'read', record.status
    assert_equal 'sent', other.status
  end
  def test_receipt_without_peer_and_multiple_groups_is_rejected
    seed_receipt
    seed_receipt(WhatsappGroup.new(id: 2, account_id: 1, inbox_id: 7, jid: '120363000000002@g.us'))
    assert_raises(HubDiagnostics::SourceMessagePending) { Whatsapp::Groups::Status.consume(@inbox, { id: 'SAME-ID', status: 'read' }) }
  end
  def test_receipt_is_scoped_to_company_and_inbox
    record = seed_receipt
    refute Whatsapp::Groups::Status.consume(OpenStruct.new(account_id: 2, id: 7), { id: 'SAME-ID', status: 'read', recipient_id: JID })
    refute Whatsapp::Groups::Status.consume(OpenStruct.new(account_id: 1, id: 8), { id: 'SAME-ID', status: 'read', recipient_id: JID })
    assert_equal 'sent', record.status
  end

  def incoming_lookup(value)
    parent = Class.new do
      attr_reader :inbox
      def initialize(inbox, value) = (@inbox, @processed_params = inbox, value)
      def find_message_by_source_id(*) = :legacy
    end
    klass = Class.new(parent) { prepend Whatsapp::Groups::Incoming }
    klass.new(@inbox, value).send(:find_message_by_source_id, 'SAME-ID')
  end
  def test_shared_group_lookup_scopes_message_and_receipt
    ContactInbox.records << ContactInbox.new(id: 70, inbox_id: 7, source_id: JID)
    @inbox.conversations = TestRelation.new([TestRecord.new(id: 71, contact_inbox_id: 70)])
    good = Message.new(id: 1, source_id: 'SAME-ID', account_id: 1, inbox_id: 7, conversation_id: 71)
    Message.records << Message.new(id: 2, source_id: 'SAME-ID', account_id: 1, inbox_id: 7, conversation_id: 99)
    Message.records << good
    assert_same good, incoming_lookup(messages: [{ connect_api: { remote_jid: JID } }])
    assert_same good, incoming_lookup(statuses: [{ recipient_id: JID }])
  end
  def test_group_lookup_does_not_replace_individual_flow
    assert_equal :legacy, incoming_lookup(messages: [{ connect_api: { remote_jid: '55119999@s.whatsapp.net' } }])
  end
  def test_invalid_group_does_not_fallback_to_individual_lookup
    assert_nil incoming_lookup(messages: [{ connect_api: { remote_jid: 'invalid@g.us' } }])
  end

  def envelope(id = 'ROUTE-1', jid: JID, **context)
    { contacts: [{ group_id: jid, group_subject: 'Equipe', profile: { name: 'Participante' } }],
      messages: [{ id: id, type: 'text', timestamp: Time.now.to_i.to_s, text: { body: 'Conteúdo' },
                   connect_api: { remote_jid: jid, participant: '123@lid' }.merge(context) }] }.with_indifferent_access
  end
  def test_management_router_does_not_call_ticket_pipeline_and_preserves_participant
    record = Whatsapp::Groups::Router.new(@inbox).dispatch(envelope) { flunk 'Ticket path executed' }
    assert_instance_of WhatsappGroupMessage, record
    assert_equal '123@lid', record.sender_jid
    assert_equal 'Conteúdo', record.content
    assert_equal 1, @group.whatsapp_group_messages.size
    assert_equal 1, @group.whatsapp_group_deliveries.size
    assert_empty Message.records
  end
  def test_group_router_duplicate_and_mode_change_keep_original_destination
    router = Whatsapp::Groups::Router.new(@inbox)
    original = router.dispatch(envelope) { flunk 'Ticket path executed' }
    @group.treatment = 'conversation'
    assert_same original, router.dispatch(envelope) { flunk 'Duplicate redirected to ticket' }
    assert_equal 1, @group.whatsapp_group_messages.size
  end
  def test_conversation_router_delegates_to_existing_flow_once
    @group.treatment = 'conversation'; count = 0
    result = Whatsapp::Groups::Router.new(@inbox).dispatch(envelope) { count += 1; :existing_flow }
    assert_equal 1, count; assert_equal :existing_flow, result
    assert_equal 0, @group.whatsapp_group_messages.size
  end
  def test_disabled_group_does_not_create_management_or_ticket_message
    @group.enabled = false
    assert_nil Whatsapp::Groups::Router.new(@inbox).dispatch(envelope) { flunk 'Ticket created for disabled group' }
    assert_equal 0, @group.whatsapp_group_messages.size
  end
  def test_old_event_after_mode_transition_is_retained_without_ticket
    @group.mode_changed_at = Time.now + 60
    Whatsapp::Groups::Router.new(@inbox).dispatch(envelope) { flunk 'Late event opened ticket' }
    assert_equal 1, @group.whatsapp_group_pending_events.size
    assert_equal 0, @group.whatsapp_group_messages.size
  end
  def test_conflicting_group_id_is_not_interpreted_as_ticket
    value = envelope; value[:messages][0][:connect_api][:remote_jid] = '120363000000002@g.us'
    assert_nil Whatsapp::Groups::Router.new(@inbox).dispatch(value) { flunk 'Conflicting group opened ticket' }
  end
  def test_individual_router_delegates_unchanged
    value = { messages: [{ id: 'DM', connect_api: { remote_jid: '55119999@s.whatsapp.net' } }] }.with_indifferent_access
    assert_equal :legacy, Whatsapp::Groups::Router.new(@inbox).dispatch(value) { :legacy }
  end

  def provider_with(response)
    client = Object.new
    client.define_singleton_method(:request) { |*args, **kwargs| response }
    Whatsapp::Groups::Provider.new(@inbox, client: client)
  end
  def outgoing
    WhatsappGroupMessage.new(whatsapp_group: @group, content: 'Resposta', reply_to_source_id: nil)
  end
  def test_provider_accepts_only_valid_acknowledgement_ids
    assert_equal 'VALID-1', provider_with('key' => { 'id' => 'VALID-1' }).send!(outgoing)
    assert_equal 'VALID-2', provider_with('data' => { 'key' => { 'id' => 'VALID-2' } }).send!(outgoing)
    [nil, false, 42, {}, '', ' ', "invalid\n", 'a' * 257].each do |bad|
      assert_raises(ConnectApi::Error) { provider_with('key' => { 'id' => bad }).send!(outgoing) }
    end
  end

  def test_malformed_acknowledgement_envelopes_raise_a_provider_error
    [nil, [], true, { 'key' => true }, { 'data' => true }, { 'data' => { 'key' => 42 } }].each do |response|
      assert_raises(ConnectApi::Error) { provider_with(response).send!(outgoing) }
    end
  end

  def protected_blob(id = 1)
    ActiveStorage::Blob.new(id: id, key: "blob-#{id}", attachments: TestRelation.new([TestRecord.new(record_type: 'WhatsappGroupMessage')]))
  end
  def public_blob(id = 2)
    ActiveStorage::Blob.new(id: id, key: "blob-#{id}", attachments: TestRelation.new([]))
  end
  def derived_blob(parent, id: 2, record_type: 'ActiveStorage::VariantRecord')
    owner = record_type == 'ActiveStorage::VariantRecord' ? TestRecord.new(blob: parent) : parent
    ActiveStorage::Blob.new(id: id, key: "blob-#{id}", attachments: TestRelation.new([TestRecord.new(record_type: record_type, record: owner)]))
  end
  def test_public_originals_remain_public_and_group_originals_are_protected
    assert Whatsapp::Groups::StorageGuard.protected?(protected_blob)
    refute Whatsapp::Groups::StorageGuard.protected?(public_blob)
  end
  def test_tracked_group_thumbnail_is_protected_via_its_original
    assert Whatsapp::Groups::StorageGuard.protected?(derived_blob(protected_blob))
    refute Whatsapp::Groups::StorageGuard.protected?(derived_blob(public_blob(3)))
  end
  def test_preview_and_preview_variant_inherit_group_protection
    preview = derived_blob(protected_blob, record_type: 'ActiveStorage::Blob')
    assert Whatsapp::Groups::StorageGuard.protected?(preview)
    assert Whatsapp::Groups::StorageGuard.protected?(derived_blob(preview, id: 3))
  end
  def test_orphaned_derivative_fails_closed
    orphan = derived_blob(nil)
    assert Whatsapp::Groups::StorageGuard.protected?(orphan)
  end

  def test_untracked_variant_key_resolves_exact_original
    blob = protected_blob; blob.key = 'nested/group/key'; ActiveStorage::Blob.records << blob
    assert_same blob, Whatsapp::Groups::StorageGuard.source_for_key("variants/#{blob.key}/#{'a' * 64}")
    assert_nil Whatsapp::Groups::StorageGuard.source_for_key("variants/#{blob.key}/not-a-digest")
    assert_nil Whatsapp::Groups::StorageGuard.source_for_key(nil)
  end
  def test_derivative_cycle_fails_closed_instead_of_hanging
    blob = public_blob
    blob.attachments = TestRelation.new([TestRecord.new(record_type: 'ActiveStorage::Blob', record: blob)])
    assert Whatsapp::Groups::StorageGuard.protected?(blob)
  end

  # Only the actual transfer action is tested here. Rails authorization and
  # cookie handling have separate request specs and need Rails/PostgreSQL.
  def download_controller(range = nil, content: 'abcdefghij')
    blob = TestRecord.new(byte_size: content.bytesize, filename: 'test.txt', content_type: 'text/plain', reads: [])
    blob.define_singleton_method(:download) { reads << :full; content }
    blob.define_singleton_method(:download_chunk) { |selected| reads << selected; content.byteslice(selected) }
    ctrl = Api::V1::GroupFilesController.new
    ctrl.instance_variable_set(:@file, TestRecord.new(blob: blob))
    ctrl.request.headers['Range'] = range if range
    [ctrl, blob]
  end
  def test_range_reads_only_the_requested_bytes
    ctrl, blob = download_controller('bytes=2-4'); ctrl.show
    assert_equal ['cde', :partial_content], [ctrl.sent_data[0], ctrl.sent_data[1][:status]]
    assert_equal [2..4], blob.reads
    assert_equal 'bytes 2-4/10', ctrl.response.headers['Content-Range']
    assert_equal '3', ctrl.response.headers['Content-Length']
  end
  def test_open_and_suffix_ranges
    [['bytes=8-', 'ij'], ['bytes=-3', 'hij'], ['bytes=0-99', 'abcdefghij']].each do |range, content|
      ctrl, blob = download_controller(range); ctrl.show
      assert_equal content, ctrl.sent_data[0]; refute_includes blob.reads, :full
    end
  end
  def test_malformed_and_unsatisfiable_ranges_do_not_read_storage
    ['bytes=10-', 'bytes=4-3', 'bytes=-0', 'bytes=-', 'bytes=0-1,3-4', 'items=0-1', 'bytes=999999999999999999999999999999-'].each do |range|
      ctrl, blob = download_controller(range); ctrl.show
      assert_equal :range_not_satisfiable, ctrl.head_status
      assert_empty blob.reads; assert_equal 'bytes */10', ctrl.response.headers['Content-Range']
    end
  end
  def test_full_download_and_no_store_headers
    ctrl, blob = download_controller; ctrl.show
    assert_equal 'abcdefghij', ctrl.sent_data[0]; assert_equal [:full], blob.reads
    assert_includes ctrl.response.headers['Cache-Control'], 'no-store'
    assert_equal 'attachment', ctrl.sent_data[1][:disposition]
  end
  def test_empty_blob_range_is_not_satisfiable
    ctrl, blob = download_controller('bytes=0-', content: ''); ctrl.show
    assert_equal :range_not_satisfiable, ctrl.head_status; assert_empty blob.reads
  end
end
