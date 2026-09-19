import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = path => fs.readFileSync(path, 'utf8');

test('forward UI returns the backend result and opens a single destination conversation', () => {
  const actions = read('app/javascript/dashboard/store/modules/conversations/actions/messageForwardActions.js');
  const modal = read('app/javascript/dashboard/components/widgets/conversation/bubble/ForwardModal.vue');

  assert.match(actions, /return response\.data/);
  assert.doesNotMatch(actions, /ignore error/);
  assert.match(modal, /selectedContactIds/);
  assert.match(modal, /dispatch\(\s*'getConversation'/);
  assert.match(modal, /frontendURL\(/);
  assert.match(modal, /conversationUrl\(/);
  assert.match(modal, /this\.\$router\.push/);
  assert.doesNotMatch(modal, /window\.history\.pushState/);
});

test('delete UI exposes provider errors and explains delete for everyone', () => {
  const menu = read('app/javascript/dashboard/modules/conversations/components/MessageContextMenu.vue');
  assert.match(menu, /deletesForEveryoneOnWhatsApp/);
  assert.match(menu, /error\?\.response\?\.data\?\.error/);
  assert.match(menu, /apagada no WhatsApp e no HUB/);
});

test('contact avatar preview uses a dedicated high-resolution source and professional overlay', () => {
  const preview = read('app/javascript/dashboard/modules/contact/components/ContactAvatarPreview.vue');
  const contactInfo = read('app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue');
  const serializer = read('app/views/api/v1/models/_contact.json.jbuilder');
  const avatarable = read('app/models/concerns/avatarable.rb');

  assert.match(preview, /previewSrc/);
  assert.match(preview, /backdrop-filter: blur/);
  assert.match(preview, /largeImageSrc/);
  assert.match(contactInfo, /:preview-src="contact\.avatar_url \|\| contact\.thumbnail"/);
  assert.match(serializer, /json\.avatar_url resource\.avatar_full_url/);
  assert.match(avatarable, /return url_for\(avatar\) if avatar\.attached\?/);
});
