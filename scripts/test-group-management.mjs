import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { groupDestination, mergeGroupMessages, groupFailure } from '../app/javascript/dashboard/helper/whatsappGroups.mjs';
const read = file => fs.readFileSync(file, 'utf8');
test('management routes never synthesize a conversation identifier', () => {
  const target = groupDestination(4, { id: 9, inbox_id: 3, treatment: 'management', conversation_id: 33 });
  assert.equal(target.name, 'inbox_dashboard'); assert.equal(target.query.groupId, '9'); assert.equal(target.params.conversation_id, undefined);
});
test('native support navigation reuses the existing conversation', () => {
  assert.equal(groupDestination(4, { id: 9, inbox_id: 3, treatment: 'conversation', conversation_id: 33 }).params.conversation_id, 33);
});
test('history selection stays separate from ticket creation', () => {
  assert.equal(groupDestination(4, { id: 9, inbox_id: 3, treatment: 'conversation', conversation_id: 33 }, true).query.groupHistory, '1');
});
test('duplicate delivery updates one client message', () => {
  assert.deepEqual(mergeGroupMessages([{ id: 1, status: 'sent' }], [{ id: 1, status: 'read' }]), [{ id: 1, status: 'read' }]);
});
test('proxy HTML is not exposed as a backend error', () => {
  assert.equal(groupFailure({ response: { data: { error: '<html>failure</html>' } } }, 'safe'), 'safe');
});
test('administrative reads and writes require native update authorization', () => {
  assert.match(read('app/controllers/api/v1/accounts/whatsapp_group_settings_controller.rb'), /authorize @inbox, :update\?/);
});
test('management persistence uses its own model, not a Conversation placeholder', () => {
  const source = read('app/services/whatsapp/groups/router.rb');
  const ingestion = source.slice(source.indexOf('    def ingest!'), source.indexOf('    def register!'));
  assert.match(ingestion, /whatsapp_group_messages\.create!/); assert.doesNotMatch(ingestion, /Conversation\.(new|create)|Message\.create!/);
});
test('file requests are scoped by account and current group access, not a public blob token', () => {
  const source = read('app/controllers/api/v1/group_files_controller.rb');
  assert.match(source, /Access\.scope\(@reader, account\)/); assert.match(source, /private, no-store/);
});
test('outgoing retry cannot automatically resend an uncertain provider side effect', () => {
  const source = read('app/jobs/whatsapp/groups/send_job.rb');
  assert.ok(source.indexOf("status: 'sending'") < source.indexOf('.send!(message)'));
  assert.match(source, /message\.status == 'queued'/); assert.match(source, /uncertain!\(message\)/);
});
