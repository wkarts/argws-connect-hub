import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import * as helpers from '../app/javascript/dashboard/helper/workspaceApps.mjs';
import * as session from '../app/javascript/dashboard/helper/workspaceSession.mjs';

// Execute the actual Vuex module with an isolated API, without installing Vue.
// Component/DOM lifecycle tests remain in the Vitest suite.
const stateSource = fs.readFileSync('app/javascript/dashboard/store/modules/workspaceApps.js', 'utf8');
const sample = (id = 1) => ({ id, name: 'Fixture', enabled: true, url: `https://app${id}.example.test`, launch_mode: 'embedded', auth_mode: 'session', integration_revision: 'a'.repeat(64) });
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
};

const memoryStorage = () => { const items = new Map(); return { getItem: key => items.get(key) || null, setItem: (key, value) => items.set(key, value), removeItem: key => items.delete(key), items }; };

async function setup(api, localStorage = memoryStorage()) {
  const context = vm.createContext({ window: { location: { origin: 'https://hub.example.test' }, localStorage } });
  const apiModule = new vm.SyntheticModule(['default'], function initialize() { this.setExport('default', api); }, { context });
  const helperModule = new vm.SyntheticModule(Object.keys(helpers), function initialize() {
    for (const [key, value] of Object.entries(helpers)) this.setExport(key, value);
  }, { context });
  const sessionModule = new vm.SyntheticModule(Object.keys(session), function initialize() {
    for (const [key, value] of Object.entries(session)) this.setExport(key, value);
  }, { context });
  const source = new vm.SourceTextModule(stateSource, { context });
  await source.link(specifier => {
    if (specifier === 'dashboard/api/workspaceApps') return apiModule;
    if (specifier === 'dashboard/helper/workspaceApps.mjs') return helperModule;
    if (specifier === 'dashboard/helper/workspaceSession.mjs') return sessionModule;
    throw new Error(`Unexpected module: ${specifier}`);
  });
  await source.evaluate();
  const { createState, mutations, actions } = source.namespace;
  const state = createState();
  const commit = (name, payload) => mutations[name](state, payload);
  commit('reset', { accountId: 1, userId: 1 });
  return { state, commit, actions, mutations };
}

test('opening, switching and returning to native screens never duplicate or rekey an existing application', async () => {
  let calls = 0;
  const ctx = await setup({ show: async (_, id) => { calls += 1; return { data: sample(id) }; } });
  await ctx.actions.open(ctx, 1);
  const key = ctx.state.tabs[0].key;
  ctx.commit('deactivate');
  await ctx.actions.open(ctx, 2);
  await ctx.actions.open(ctx, 1);
  assert.equal(calls, 2);
  assert.equal(ctx.state.tabs.length, 2);
  assert.equal(ctx.state.tabs[0].key, key);
  assert.equal(ctx.state.activeId, 1);
});

test('only deliberate reload creates a new frame key', async () => {
  const ctx = await setup({});
  ctx.commit('open', sample());
  const key = ctx.state.tabs[0].key;
  ctx.commit('catalog', [{ ...sample(), name: 'Changed label' }]);
  assert.equal(ctx.state.tabs[0].key, key);
  ctx.commit('reload', 1);
  assert.notEqual(ctx.state.tabs[0].key, key);
  ctx.commit('close', 1);
  assert.equal(ctx.state.tabs.length, 0);
});

test('switching company or logging out removes all frames and local user state', async () => {
  const ctx = await setup({});
  ctx.commit('open', sample());
  ctx.commit('reset', { accountId: 2, userId: 1 });
  assert.equal(ctx.state.tabs.length, 0);
  assert.equal(ctx.state.scope, '2:1');
  ctx.commit('open', sample());
  ctx.commit('reset');
  assert.equal(ctx.state.tabs.length, 0);
  assert.equal(ctx.state.scope, '');
});

test('an offline refresh does not close running applications', async () => {
  const ctx = await setup({ list: async () => { throw new Error('offline'); } });
  ctx.commit('open', sample());
  const key = ctx.state.tabs[0].key;
  await ctx.actions.refresh(ctx);
  assert.equal(ctx.state.tabs[0].key, key);
  assert.equal(ctx.state.failed, true);
});

test('server-side access revocation invalidates open tabs', async () => {
  const ctx = await setup({ list: async () => { throw { response: { status: 403 } }; } });
  ctx.commit('open', sample());
  await ctx.actions.refresh(ctx);
  assert.equal(ctx.state.tabs.length, 0);
  assert.equal(ctx.state.activeId, null);
});

test('late responses from A cannot restore a catalog after A to B to A switching', async () => {
  const response = deferred();
  const ctx = await setup({ list: () => response.promise });
  const request = ctx.actions.refresh(ctx);
  ctx.commit('reset', { accountId: 2, userId: 1 });
  ctx.commit('reset', { accountId: 1, userId: 1 });
  response.resolve({ data: [sample()] });
  await request;
  assert.equal(ctx.state.apps.length, 0);
});

test('a delayed launch cannot steal focus after returning to conversations', async () => {
  const response = deferred();
  const ctx = await setup({ show: () => response.promise });
  const request = ctx.actions.open(ctx, 1);
  ctx.commit('deactivate');
  response.resolve({ data: sample() });
  await request;
  assert.equal(ctx.state.activeId, null);
  assert.equal(ctx.state.tabs.length, 0);
});

test('overlapping catalog requests use the most recent response', async () => {
  const older = deferred();
  let count = 0;
  const ctx = await setup({ list: () => (++count === 1 ? older.promise : Promise.resolve({ data: [sample(2)] })) });
  const request = ctx.actions.refresh(ctx);
  await ctx.actions.refresh(ctx);
  older.resolve({ data: [sample(1)] });
  await request;
  assert.equal(ctx.state.apps.length, 1);
  assert.equal(ctx.state.apps[0].id, 2);
});


test('restores authorized application identities and active selection in a new runtime', async () => {
  const local = memoryStorage();
  const api = { list: async () => ({ data: [sample(), sample(2)] }) };
  const first = await setup(api, local);
  await first.actions.refresh(first);
  first.commit('open', sample(2));
  first.commit('open', sample(1));
  first.commit('reset'); // Closing the runtime does not erase the already saved session.
  const next = await setup(api, local);
  assert.equal(next.state.tabs.length, 0); // Server must authorize first.
  await next.actions.refresh(next);
  assert.equal(JSON.stringify(next.state.tabs.map(tab => tab.id)), '[2,1]');
  assert.equal(next.state.activeId, 1);
  const saved = JSON.stringify([...local.items]);
  for (const forbidden of ['url', 'https:', 'password', 'api_key', 'token']) assert.equal(saved.includes(forbidden), false);
});

test('does not reopen explicitly closed tabs and keeps native view active', async () => {
  const local = memoryStorage();
  const api = { list: async () => ({ data: [sample(), sample(2)] }) };
  const ctx = await setup(api, local);
  await ctx.actions.refresh(ctx); ctx.commit('open', sample()); ctx.commit('open', sample(2)); ctx.commit('close', 1); ctx.commit('deactivate');
  const next = await setup(api, local); await next.actions.refresh(next);
  assert.equal(JSON.stringify(next.state.tabs.map(tab => tab.id)), '[2]');
  assert.equal(next.state.activeId, null);
});

test('does not restore changed, disabled, removed, external or unauthorized applications', async () => {
  const local = memoryStorage();
  const original = [1, 2, 3, 4, 5].map(sample);
  const ctx = await setup({ list: async () => ({ data: original }) }, local);
  await ctx.actions.refresh(ctx); original.forEach(app => ctx.commit('open', app));
  const next = await setup({ list: async () => ({ data: [sample(), { ...sample(2), enabled: false }, { ...sample(3), integration_revision: 'b'.repeat(64) }, { ...sample(4), launch_mode: 'external' }] }) }, local);
  await next.actions.refresh(next);
  assert.equal(JSON.stringify(next.state.tabs.map(tab => tab.id)), '[1]');
  assert.equal(next.state.activeId, null);
});

test('failed initial authorization preserves the snapshot until connectivity is restored', async () => {
  const local = memoryStorage(); let online = true;
  const api = { list: async () => { if (!online) throw new Error('offline'); return { data: [sample()] }; } };
  const ctx = await setup(api, local); await ctx.actions.refresh(ctx); ctx.commit('open', sample());
  const original = JSON.stringify([...local.items]);
  const next = await setup(api, local); online = false; await next.actions.refresh(next);
  assert.equal(next.state.tabs.length, 0); assert.equal(next.state.sessionRestored, false);
  assert.equal(JSON.stringify([...local.items]), original);
  online = true; await next.actions.refresh(next); assert.equal(next.state.tabs.length, 1);
});

test('saved tabs cannot cross company or user boundaries', async () => {
  const local = memoryStorage(); const api = { list: async () => ({ data: [sample()] }) };
  const ctx = await setup(api, local); await ctx.actions.refresh(ctx); ctx.commit('open', sample());
  for (const scope of [{ accountId: 2, userId: 1 }, { accountId: 1, userId: 2 }]) {
    ctx.commit('reset', scope); await ctx.actions.refresh(ctx); assert.equal(ctx.state.tabs.length, 0);
  }
  ctx.commit('reset', { accountId: 1, userId: 1 }); await ctx.actions.refresh(ctx); assert.equal(ctx.state.tabs.length, 1);
});

test('blocked browser storage is nonfatal and corrupt snapshots do not navigate', async () => {
  const broken = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('full'); } };
  const ctx = await setup({ list: async () => ({ data: [sample()] }) }, broken);
  await ctx.actions.refresh(ctx); ctx.commit('open', sample()); assert.equal(ctx.state.tabs.length, 1);
  for (const raw of ['not-json', '{"version":999,"tabs":[]}', '{"version":1,"tabs":[{"id":1,"revision":"x","url":"https://injected.test"}]}']) {
    const local = memoryStorage(); local.setItem('hub:workspace:session:v1:1:1', raw);
    const next = await setup({ list: async () => ({ data: [sample()] }) }, local);
    await next.actions.refresh(next); assert.equal(next.state.tabs.length, 0);
  }
});
