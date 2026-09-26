import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { reconcileWorkspaceTabs, safeApplicationUrl, validateLoginPayload, workspaceScope } from '../app/javascript/dashboard/helper/workspaceApps.mjs';

const read = path => fs.readFileSync(path, 'utf8');
const app = { id: 1, name: 'Internal test fixture', enabled: true, url: 'https://app.example.test/home', launch_mode: 'embedded', auth_mode: 'form_post', login_url: 'https://app.example.test/sign-in', username_field: 'username', password_field: 'password', integration_revision: 'v1' };
const tab = { id: app.id, key: 'stable-frame', app };
const payload = { action: app.login_url, username_field: app.username_field, password_field: app.password_field, username: 'test-user', password: 'not-a-real-password', integration_revision: 'v1' };

test('workspace scope includes company and user and rejects invalid identifiers', () => {
  assert.equal(workspaceScope(1, 2), '1:2');
  assert.notEqual(workspaceScope(1, 2), workspaceScope(2, 2));
  for (const value of [null, 0, -1, 'no', Infinity]) assert.equal(workspaceScope(value, 2), '');
});

test('application URLs require HTTPS and cannot use HUB origin or inline credentials', () => {
  const origin = 'https://hub.example.test';
  assert.equal(safeApplicationUrl(app.url, origin), true);
  for (const value of ['javascript:alert(1)', 'data:text/html,test', 'http://app.example.test', 'https://user:password@app.example.test', '//app.example.test', 'https://hub.example.test/apps', 'https://app.example.test\\evil']) {
    assert.equal(safeApplicationUrl(value, origin), false, value);
  }
});

test('catalog updates preserve frame identity for cosmetic changes', () => {
  const [updated] = reconcileWorkspaceTabs([tab], [{ ...app, name: 'New label', icon_name: 'mail' }]);
  assert.equal(updated.key, tab.key);
  assert.equal(updated.app.name, 'New label');
});

test('revocation, deletion, target changes and external mode remove old frames', () => {
  for (const updated of [{ ...app, enabled: false }, { ...app, launch_mode: 'external' }, { ...app, integration_revision: 'changed' }]) {
    assert.deepEqual(reconcileWorkspaceTabs([tab], [updated]), []);
  }
  assert.deepEqual(reconcileWorkspaceTabs([tab], []), []);
});

test('credential submission is bound to the exact authorized destination and revision', () => {
  assert.equal(validateLoginPayload(app, payload, 'https://hub.example.test'), true);
  for (const changes of [{ action: 'https://other.example.test/sign-in' }, { action: 'https://app.example.test/other' }, { integration_revision: 'v2' }, { password_field: 'other' }]) {
    assert.equal(validateLoginPayload(app, { ...payload, ...changes }, 'https://hub.example.test'), false);
  }
});

test('host is independent of native route instances and frames hide without unmounting', () => {
  const host = read('app/javascript/dashboard/components/workspace/WorkspaceHost.vue');
  const root = read('app/javascript/dashboard/App.vue');
  assert.match(host, /v-show="tab.id === activeId"/);
  assert.match(host, /:key="tab.key"/);
  assert.doesNotMatch(host, /<router-view|:key=".*\$route/);
  assert.ok(root.indexOf('<WorkspaceHost') > root.indexOf('<LoadingState v-else'));
  assert.doesNotMatch(read('app/javascript/dashboard/store/modules/workspaceApps.js'), /localStorage|sessionStorage|password/);
});

test('contact uploader owns the single preview and preserves upload/delete controls', () => {
  const form = read('app/javascript/dashboard/routes/dashboard/conversation/contact/ContactForm.vue');
  const uploader = read('app/javascript/dashboard/components/widgets/forms/AvatarUploader.vue');
  const preview = read('app/javascript/dashboard/modules/contact/components/ContactAvatarPreview.vue');
  assert.equal((form.match(/<ContactAvatarPreview/g) || []).length, 1);
  assert.match(form, /<template #preview>/);
  assert.match(uploader, /<slot name="preview">/);
  assert.match(uploader, /@change="handleImageUpload"/);
  assert.match(uploader, /@click="onAvatarDelete"/);
  assert.doesNotMatch(form, /PREVIEW_HELP/);
  assert.doesNotMatch(preview, /zoom-badge|icon="zoom-in"|cursor: zoom-in/);
  assert.match(preview, /@click="openPreview"/);
});

test('all supported locales have complete application labels and no seeded products', () => {
  const labels = ['en', 'es', 'pt', 'pt_BR'].map(locale => JSON.parse(read(`app/javascript/dashboard/i18n/locale/${locale}/workspaceApps.json`)).WORKSPACE_APPS);
  const keys = Object.keys(labels[0]).sort();
  labels.forEach(label => assert.deepEqual(Object.keys(label).sort(), keys));
  const migration = read('db/migrate/20260925180000_create_workspace_apps.rb');
  assert.doesNotMatch(migration, /WorkspaceApp\.create|PIGE360|Scheduler/i);
});
