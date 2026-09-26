import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import * as helpers from '../app/javascript/dashboard/helper/workspaceApps.mjs';

// Execute the actual Vuex module with an isolated API, without installing Vue.
// Component/DOM lifecycle tests remain in the Vitest suite.
const stateSource = fs.readFileSync('app/javascript/dashboard/store/modules/workspaceApps.js', 'utf8');
const sample = (id = 1) => ({ id, name: 'Fixture', enabled: true, url: `https://app${id}.example.test`, launch_mode: 'embedded', auth_mode: 'session', integration_revision: '1' });
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
};

async function setup(api) {
  const context = vm.createContext({ window: { location: { origin: 'https://hub.example.test' } } });
  const apiModule = new vm.SyntheticModule(['default'], function initialize() { this.setExport('default', api); }, { context });
  const helperModule = new vm.SyntheticModule(Object.keys(helpers), function initialize() {
    for (const [key, value] of Object.entries(helpers)) this.setExport(key, value);
  }, { context });
  const source = new vm.SourceTextModule(stateSource, { context });
  await source.link(specifier => {
    if (specifier === 'dashboard/api/workspaceApps') return apiModule;
    if (specifier === 'dashboard/helper/workspaceApps.mjs') return helperModule;
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
