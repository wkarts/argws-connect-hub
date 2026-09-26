// Isolated behavioral tests of the actual component methods, with API doubles.
// No Vue renderer, DOM, HTTP server or authentication integration is exercised.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
import { webcrypto } from 'node:crypto';
import * as helpers from '../app/javascript/dashboard/helper/whatsappGroups.mjs';

const source = fs.readFileSync(new URL('../app/javascript/dashboard/components/whatsappGroups/GroupThread.vue', import.meta.url), 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
const deferred = () => { let resolve, reject; const promise = new Promise((ok, no) => { resolve = ok; reject = no; }); return { promise, resolve, reject }; };
const group = () => ({ id: 9, inbox_id: 3, name: 'Teste', treatment: 'management', can_reply: true, muted: false });
const message = (id = 1) => ({ id, content: 'Conteúdo privado', source_id: `MSG-${id}`, files: [] });
async function setup(overrides = {}) {
  const calls = [];
  const api = {
    show: async () => ({ data: group() }), messages: async () => ({ data: { messages: [], next_before: null } }),
    preference: async () => ({ data: { muted: true } }), message: async () => ({ data: message() }),
    send: async (...args) => { calls.push(args); return { data: message(2) }; }, ...overrides,
  };
  const context = vm.createContext({ window: { crypto: webcrypto }, document: { hidden: false }, FormData,
    setTimeout, clearTimeout, Uint8Array, Date, console });
  const synthetic = values => new vm.SyntheticModule(Object.keys(values), function () { for (const [name, value] of Object.entries(values)) this.setExport(name, value); }, { context });
  const component = new vm.SourceTextModule(source, { context });
  const imports = {
    'dashboard/api/whatsappGroups': synthetic({ default: api }),
    'dashboard/helper/whatsappGroups.mjs': synthetic(helpers),
    'shared/constants/busEvents': synthetic({ BUS_EVENTS: { WEBSOCKET_RECONNECT: 'reconnect' } }),
    './GroupConfirm.vue': synthetic({ default: {} }),
  };
  await component.link(name => { assert.ok(imports[name], `Unmocked import: ${name}`); return imports[name]; });
  await component.evaluate();
  const definition = component.namespace.default;
  const state = Object.assign(definition.data(), { groupId: 9, $store: { getters: { getCurrentAccountId: 1 } },
    $t: name => name, $refs: {}, $nextTick: async () => {}, scheduled: 0 });
  for (const [name, fn] of Object.entries(definition.methods)) state[name] = fn.bind(state);
  for (const [name, fn] of Object.entries(definition.computed)) Object.defineProperty(state, name, { get: fn.bind(state) });
  // Scheduler only is replaced: tests control refresh timing explicitly.
  state.scheduleRefresh = () => { state.scheduled += 1; };
  state.group = group(); state.messages = [message()]; state.text = 'Nova mensagem';
  return { state, api, calls, definition };
}

test('late send cannot restore private content after realtime revocation', async () => {
  const pending = deferred(); const { state } = await setup({ send: () => pending.promise });
  const send = state.send();
  state.changed({ account_id: 1, inbox_id: 3, group_id: 9, invalidated: true });
  assert.equal(state.group, null); assert.equal(state.messages.length, 0); assert.equal(state.text, '');
  pending.resolve({ data: message(2) }); await send;
  assert.equal(state.group, null); assert.equal(state.messages.length, 0); assert.equal(state.sending, false);
});

test('REST denial during realtime fetch invalidates a pending send response too', async () => {
  const pending = deferred(); const { state } = await setup({ send: () => pending.promise,
    message: async () => { throw { response: { status: 403 } }; } });
  const send = state.send(); await state.syncMessage(1);
  pending.resolve({ data: message(2) }); await send;
  assert.equal(state.group, null); assert.equal(state.messages.length, 0); assert.equal(state.text, '');
});

test('REST denial during full refresh invalidates a pending send response', async () => {
  const pending = deferred(); const { state } = await setup({ send: () => pending.promise,
    show: async () => { throw { response: { status: 404 } }; } });
  const send = state.send(); await state.refresh(); pending.resolve({ data: message(2) }); await send;
  assert.equal(state.group, null); assert.equal(state.messages.length, 0);
});

test('same account/group numbers do not make a pre-revocation response current', async () => {
  const pending = deferred(); const { state } = await setup({ send: () => pending.promise });
  const send = state.send(); state.changed({ account_id: 1, inbox_id: 3, group_id: 9, invalidated: true });
  state.group = group(); state.messages = [message(10)]; // A fresh authorized read occurred.
  pending.resolve({ data: message(2) }); await send;
  assert.equal(JSON.stringify(state.messages.map(row => row.id)), '[10]');
});

test('network retry keeps the same client id but a changed draft gets a new id', async () => {
  const sent = []; const { state } = await setup({ send: async (...args) => { sent.push(args); throw new Error('offline'); } });
  await state.send(); await state.send();
  const id = sent[0][2].get('group_message[client_id]'); assert.match(id, /^[a-f0-9-]{36}$/);
  assert.equal(sent[1][2].get('group_message[client_id]'), id);
  state.text = 'Outra mensagem'; await state.send(); assert.notEqual(sent[2][2].get('group_message[client_id]'), id);
  assert.equal(sent[0][0], 1); assert.equal(sent[0][1], 9);
});

test('double click while pending makes one API call', async () => {
  const pending = deferred(); let count = 0;
  const { state } = await setup({ send: () => { count += 1; return pending.promise; } });
  const send = state.send(); await state.send(); assert.equal(count, 1); pending.resolve({ data: message(2) }); await send;
});

test('old send completion cannot clear a new group send busy state', async () => {
  const old = deferred(), next = deferred(); let count = 0;
  const { state, definition } = await setup({ send: () => (++count === 1 ? old.promise : next.promise) });
  const first = state.send(); state.groupId = 10; state.refresh = async () => {};
  definition.watch.scope.handler.call(state); state.group = { ...group(), id: 10 }; state.text = 'Novo grupo';
  const second = state.send(); old.resolve({ data: message(2) }); await first;
  assert.equal(state.sending, true); assert.equal(state.messages.length, 0);
  next.resolve({ data: message(20) }); await second; assert.equal(state.sending, false);
  assert.equal(JSON.stringify(state.messages.map(row => row.id)), '[20]');
});

test('switching to legacy history cannot mix in a management send response', async () => {
  const pending = deferred(); const { state } = await setup({ send: () => pending.promise });
  const send = state.send(); state.legacy = true; state.messages = [message(50)];
  pending.resolve({ data: message(2) }); await send; assert.equal(JSON.stringify(state.messages.map(row => row.id)), '[50]');
});

test('late full refresh after invalidation is ignored', async () => {
  const pending = deferred(); const { state } = await setup({ show: () => pending.promise });
  const read = state.refresh(); state.changed({ account_id: 1, inbox_id: 3, group_id: 9, invalidated: true });
  pending.resolve({ data: group() }); await read; assert.equal(state.group, null); assert.equal(state.messages.length, 0);
});

test('unrelated company/group/inbox event leaves the current private view intact', async () => {
  const { state } = await setup(); const epoch = state.accessEpoch;
  for (const event of [{ account_id: 2, inbox_id: 3, group_id: 9 }, { account_id: 1, inbox_id: 3, group_id: 10 }, { account_id: 1, inbox_id: 4, group_id: 9 }]) state.changed({ ...event, invalidated: true });
  assert.equal(state.accessEpoch, epoch); assert.equal(state.messages.length, 1); assert.equal(state.scheduled, 0);
});

test('conversation, read-only and legacy views never call management send', async () => {
  const { state, calls } = await setup();
  for (const attributes of [{ treatment: 'conversation' }, { treatment: 'management', can_reply: false }]) {
    state.group = { ...group(), ...attributes }; await state.send();
  }
  state.group = group(); state.legacy = true; await state.send(); assert.equal(calls.length, 0);
});

test('old completion after destroyed component cannot repopulate messages', async () => {
  const pending = deferred(); const { state } = await setup({ send: () => pending.promise });
  const send = state.send(); state.alive = false; state.messages = []; pending.resolve({ data: message(2) }); await send;
  assert.equal(state.messages.length, 0);
});
