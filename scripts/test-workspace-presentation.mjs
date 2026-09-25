import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import { menuPosition, safeDiagnosticUrl, toolbarPreference, workspaceTooltip } from '../app/javascript/dashboard/helper/workspacePresentation.mjs';
import { navigationMessage, NAVIGATION_CHANNEL } from '../app/javascript/dashboard/helper/workspaceNavigation.mjs';
const read = path => fs.readFileSync(path, 'utf8');
const root = 'app/javascript/dashboard/components/workspace/';

test('hints use native tooltip styles at body level and never intercept hover', () => {
  const hint = workspaceTooltip('Long application name');
  assert.equal(hint.container, 'body');
  assert.equal(hint.delay.hide, 0);
  assert.equal(hint.placement, 'right');
  assert.equal(workspaceTooltip('RTL', true).placement, 'left');
  assert.match(read(`${root}WorkspaceHost.vue`), /\.tooltip\.workspace-tooltip\s*\{\s*pointer-events: none !important/);
});

test('toolbar pin preference is isolated by company/user and tolerates unavailable storage', () => {
  const values = new Map();
  globalThis.localStorage = { getItem: key => values.get(key), setItem: (key, value) => values.set(key, value) };
  assert.equal(toolbarPreference('1:1'), false);
  assert.equal(toolbarPreference('1:1', true), true);
  assert.equal(toolbarPreference('2:1'), false);
  assert.equal(toolbarPreference('1:2'), false);
  assert.equal(toolbarPreference('1:1', false), false);
  delete globalThis.localStorage;
  assert.equal(toolbarPreference('1:1'), false);
});

test('content stays below native menus and confirmation remains outside its stacking context', () => {
  const host = read(`${root}WorkspaceHost.vue`);
  assert.match(host, /z-index: var\(--z-index-low, 10\)/);
  assert.doesNotMatch(host, /z-index: 35/);
  assert.match(host, /<div class="workspace-shell">/);
  assert.match(host, /<\/div>\s*<!-- Dialogs and context menus/);
  assert.match(read(`${root}WorkspaceLauncher.vue`), /z-index: 20/);
  assert.match(read('app/javascript/dashboard/components/layout/sidebarComponents/OptionsMenu.vue'), /z-30/);
});

test('rails hide scrollbars while retaining wheel, touch and keyboard navigation', () => {
  const rail = read(`${root}WorkspaceRail.vue`);
  for (const text of ['overflow-y: auto', 'scrollbar-width: none', 'touch-action: pan-y', 'overscroll-behavior: contain', 'PageDown', 'ArrowDown']) assert.ok(rail.includes(text), text);
  assert.match(read(`${root}WorkspaceSidebar.vue`), /@contextmenu.prevent.stop/);
});

test('compact toolbar and larger uploaded image preserve the original aspect ratio', () => {
  assert.match(read(`${root}WorkspaceToolbar.vue`), /height: 38px/);
  assert.match(read(`${root}WorkspaceToolbar.vue`), /font-size: 12px/);
  assert.match(read(`${root}WorkspaceIcon.vue`), /default: 28/);
  assert.match(read(`${root}WorkspaceIcon.vue`), /object-fit: contain/);
});

test('context menu is clamped and diagnostics omit URL queries and fragments', () => {
  assert.deepEqual(menuPosition(3000, 3000, 800, 600), { left: '568px', top: '390px' });
  assert.equal(safeDiagnosticUrl('https://example.test/path?token=private#secret'), 'https://example.test/path');
});

test('navigation bridge rejects wrong origin, frame, nonce and malformed capabilities', () => {
  const contentWindow = {};
  const frame = { contentWindow };
  const origin = 'https://app.example.test';
  const data = { channel: NAVIGATION_CHANNEL, type: 'state', nonce: 'test', supported: true, back: true, forward: false };
  const event = { source: contentWindow, origin, data };
  assert.equal(navigationMessage(event, frame, origin, 'test'), true);
  for (const changed of [{ origin: 'https://wrong.test' }, { source: {} }, { data: { ...data, nonce: 'wrong' } }, { data: { ...data, back: 'yes' } }]) {
    assert.equal(navigationMessage({ ...event, ...changed }, frame, origin, 'test'), false);
  }
  assert.equal(navigationMessage(event, frame, origin, ''), false);
  assert.doesNotMatch(read(`${root}WorkspaceFrame.vue`), /window\.history\.(back|forward|go)\(/);
});

test('every literal fluent icon in workspace templates exists in the dashboard registry', () => {
  const icons = JSON.parse(read('app/javascript/shared/components/FluentIcon/dashboard-icons.json'));
  for (const file of fs.readdirSync(root).filter(name => name.endsWith('.vue'))) {
    for (const match of read(`${root}${file}`).matchAll(/<fluent-icon[^>]*?\sicon="([a-z-]+)"/g)) assert.ok(icons[`${match[1]}-outline`], `${file}: ${match[1]}`);
  }
});
