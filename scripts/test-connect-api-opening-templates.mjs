// Dependency-free tests against the actual Vue options/getters, not a reimplementation.
// These do not replace a production bundle or browser visual validation.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const read = path => readFileSync(new URL(path, root), 'utf8');
const base = 'app/javascript/dashboard/';
const settingsPath = `${base}routes/dashboard/settings/inbox/settingsPage/`;
const contactPath = `${base}routes/dashboard/conversation/contact/`;
const callPath = `${base}components/widgets/conversation/ConnectApiCallPanelPolished.vue`;
const script = text => text.match(/<script[^>]*>([\s\S]*?)<\/script>/)?.[1] ?? text;
const noImports = text => text.replace(/^import[\s\S]*?from ['"][^'"]+['"];\s*/gm, '');
function component(path, globals = {}) {
  const code = noImports(script(read(path))).replace('export default', 'globalThis.component =');
  const context = { console, mapGetters: () => ({}), ...globals };
  vm.runInNewContext(code, context, { filename: path });
  return context.component;
}
const moduleText = read(`${base}store/modules/inboxes.js`);
const getterCode = moduleText.slice(moduleText.indexOf('export const getters ='), moduleText.indexOf('export const actions ='));
const context = { INBOX_TYPES: {}, Array };
vm.runInNewContext(getterCode.replace('export const getters =', 'globalThis.getters ='), context);
const getters = context.getters;
const template = (name = 'hello', language = 'pt_BR') => ({ name, language, status: 'APPROVED', components: [{ type: 'BODY', text: 'From API' }] });
const names = values => Array.from(values, item => item.name);

test('opening uses the server-filtered per-inbox catalog, not all templates', () => {
  const state = { records: [{ id: 1, provider: 'connectapi', message_templates: [template(), template('aviso')], opening_templates: [template('aviso')] }] };
  assert.deepEqual(names(getters.getWhatsAppTemplates(state)(1, true)), ['aviso']);
  assert.deepEqual(names(getters.getWhatsAppTemplates(state)(1)), ['hello', 'aviso']);
});
test('missing/empty opening catalog fails closed without fallback to additional attributes', () => {
  for (const opening_templates of [undefined, null, []]) {
    const state = { records: [{ id: 1, provider: 'connectapi', opening_templates, message_templates: [template()], additional_attributes: { message_templates: [template()] } }] };
    assert.equal(getters.getWhatsAppTemplates(state)(1, true).length, 0);
  }
});
test('one inbox cannot select another inbox catalog', () => {
  const state = { records: [{ id: 1, provider: 'connectapi', opening_templates: [template('one')] }, { id: 2, provider: 'connectapi', opening_templates: [template('two')] }] };
  assert.deepEqual(names(getters.getWhatsAppTemplates(state)(2, true)), ['two']);
  assert.equal(getters.getWhatsAppTemplates(state)(3, true).length, 0);
});
test('Meta templates keep their original catalog path', () => {
  const state = { records: [{ id: 1, provider: 'whatsapp_cloud', message_templates: [template('meta')], opening_templates: [] }] };
  assert.deepEqual(names(getters.getWhatsAppTemplates(state)(1, true)), ['meta']);
});
test('unsupported components do not crash or appear in the picker', () => {
  const state = { records: [{ id: 1, provider: 'connectapi', opening_templates: [template(), { name: 'bad', components: null }, { ...template('image'), components: [{ format: 'IMAGE' }] }] }] };
  assert.deepEqual(names(getters.getWhatsAppTemplates(state)(1, true)), ['hello']);
});
test('picker filters pending/rejected templates and preserves absent statuses only for Connect API', () => {
  const picker = component(`${base}components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue`);
  const all = [template(), { ...template('pending'), status: 'PENDING' }, { ...template('nostatus'), status: undefined }, { ...template('nobody'), components: [] }];
  const self = { inboxId: 1, openingOnly: true, isConnectApi: true, $store: { getters: { 'inboxes/getWhatsAppTemplates': (id, only) => {
    assert.equal(id, 1); assert.equal(only, true); return all;
  } } } };
  assert.deepEqual(names(picker.computed.whatsAppTemplateMessages.call(self)), ['hello', 'nostatus']);
  self.isConnectApi = false;
  assert.deepEqual(names(picker.computed.whatsAppTemplateMessages.call(self)), ['hello']);
});
test('changing inbox clears a selected opening template', () => {
  const wrapper = component(`${contactPath}WhatsappTemplates.vue`, { TemplatesPicker: {}, TemplateParser: {} });
  const events = [];
  const self = { selectedWaTemplate: template(), $emit: (...args) => events.push(args) };
  self.onResetTemplate = wrapper.methods.onResetTemplate.bind(self);
  wrapper.watch.inboxId.call(self);
  assert.equal(self.selectedWaTemplate, null);
  assert.equal(events[0][1], false);
  assert.match(read(`${contactPath}WhatsappTemplates.vue`), /opening-only/);
});
test('new conversation cannot fall back to free text just because Connect API returns no templates', () => {
  const code = script(read(`${contactPath}ConversationForm.vue`));
  const body = code.match(/hasWhatsappTemplates\(\) \{([\s\S]*?)\n    \}/)[1];
  const hasTemplates = new Function(body);
  assert.equal(hasTemplates.call({ selectedInbox: { inbox: { provider: 'connectapi', message_templates: null } } }), true);
  assert.equal(hasTemplates.call({ selectedInbox: { inbox: { provider: 'email' } } }), false);
});
test('admin load ignores late results from a different inbox', async () => {
  let resolve;
  const admin = component(`${settingsPath}ConnectApiOpeningTemplates.vue`, { InboxAPI: { getOpeningTemplates: () => new Promise(done => { resolve = done; }) }, useAlert: () => {} });
  const self = { ...admin.data(), inbox: { id: 1 } };
  self.applyCatalog = admin.methods.applyCatalog.bind(self);
  const pending = admin.methods.loadTemplates.call(self);
  self.inbox = { id: 2 };
  resolve({ data: { payload: [template('wrong-inbox')] } });
  await pending;
  assert.equal(self.templates.length, 0);
});
test('failed save restores the switch and does not mutate the persisted preference', async () => {
  const admin = component(`${settingsPath}ConnectApiOpeningTemplates.vue`, { InboxAPI: {}, useAlert: () => {} });
  const persisted = { ...template(), hub_opening_enabled: false };
  const self = { ...admin.data(), inbox: { id: 1 }, templates: [persisted], $store: { dispatch: async () => { throw new Error('network'); } } };
  self.key = admin.methods.key;
  const event = { target: { checked: true } };
  await admin.methods.setEnabled.call(self, persisted, event);
  assert.equal(event.target.checked, false);
  assert.equal(persisted.hub_opening_enabled, false);
  assert.equal(self.savingKey, null);
});
test('disconnect sends the existing payload once and always resets its busy state', async () => {
  const settings = component(`${settingsPath}ConnectApiConfiguration.vue`, { ConnectApiOpeningTemplates: {}, useAlert: () => {} });
  let resolve;
  let calls = 0;
  const self = { isDisconnecting: false, isReconciling: false, update: payload => {
    assert.equal(payload.disconnect, true); assert.equal(payload.connect, false); calls += 1;
    return new Promise(done => { resolve = done; });
  } };
  const first = settings.methods.disconnect.call(self);
  await settings.methods.disconnect.call(self);
  assert.equal(calls, 1);
  assert.equal(self.isDisconnecting, true);
  resolve(false);
  await first;
  assert.equal(self.isDisconnecting, false);
});
test('reconcile refreshes the real admin catalog only after a successful backend update', async () => {
  const settings = component(`${settingsPath}ConnectApiConfiguration.vue`, { ConnectApiOpeningTemplates: {}, useAlert: () => {} });
  let loads = 0;
  const self = { isReconciling: false, isDisconnecting: false, update: async () => true, $refs: { openingTemplates: { loadTemplates: async () => { loads += 1; } } } };
  await settings.methods.reconcile.call(self);
  assert.equal(loads, 1);
  self.update = async () => false;
  await settings.methods.reconcile.call(self);
  assert.equal(loads, 1);
  assert.equal(self.isReconciling, false);
});
test('mute and disconnect retain their actions with contained light/dark visual states', () => {
  const calls = read(callPath);
  const button = calls.match(/<button\s+v-if="mediaCallId === callId\(primaryCall\)"[\s\S]*?<\/button>/)?.[0];
  assert.ok(button);
  for (const token of ['rounded-xl', 'px-4', 'py-2.5', 'dark:bg-slate-700', ':aria-pressed', "action(primaryCall, 'mute')", 'animate-spin']) assert.ok(button.includes(token), token);
  const settings = read(`${settingsPath}ConnectApiConfiguration.vue`);
  const disconnect = settings.match(/<button[^>]*[\s\S]*?@click="disconnect"[\s\S]*?<\/button>/)?.[0];
  assert.ok(disconnect?.includes('bg-red-600'));
  assert.ok(disconnect?.includes('animate-spin'));
});
test('modified Vue/JavaScript scripts have valid JavaScript syntax', () => {
  const paths = [
    `${base}api/inboxes.js`, `${base}store/modules/inboxes.js`, callPath,
    `${base}components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue`,
    `${settingsPath}ConnectApiConfiguration.vue`, `${settingsPath}ConnectApiOpeningTemplates.vue`,
    `${contactPath}ConversationForm.vue`, `${contactPath}WhatsappTemplates.vue`,
  ];
  for (const path of paths) {
    const code = noImports(script(read(path))).replace(/export default/g, 'globalThis.result =').replace(/export const/g, 'const');
    assert.doesNotThrow(() => new vm.Script(code, { filename: path }), path);
  }
});
