import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

// Parse ES modules and Vue script blocks. This does not replace Vue template compilation.
const root = 'app/javascript/dashboard';
const collect = dir => fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
  const file = path.join(dir, entry.name);
  return entry.isDirectory() ? collect(file) : [file];
});
const files = [
  `${root}/api/whatsappGroups.js`, `${root}/helper/whatsappGroups.mjs`, `${root}/helper/actionCable.js`,
  `${root}/helper/AudioAlerts/DashboardAudioNotificationHelper.js`, `${root}/components/ChatList.vue`,
  `${root}/routes/dashboard/conversation/ConversationView.vue`, `${root}/routes/dashboard/settings/inbox/Settings.vue`,
  `${root}/routes/dashboard/settings/inbox/settingsPage/WhatsappGroupSettings.vue`,
  `${root}/store/modules/conversations/index.js`, `${root}/store/modules/notifications/mutations.js`,
  ...collect(`${root}/components/whatsappGroups`),
  'public/workspace-navigation-bridge.js', `${root}/helper/workspacePresentation.mjs`, `${root}/helper/workspaceNavigation.mjs`,
  `${root}/App.vue`, `${root}/api/workspaceApps.js`, `${root}/helper/workspaceApps.mjs`,
  `${root}/store/index.js`, `${root}/store/modules/workspaceApps.js`,
  `${root}/components/layout/Sidebar.vue`, `${root}/components/layout/config/sidebarItems/settings.js`,
  `${root}/components/layout/sidebarComponents/Primary.vue`, `${root}/components/layout/sidebarComponents/PrimaryNavItem.vue`,
  `${root}/components/widgets/forms/AvatarUploader.vue`, `${root}/modules/contact/components/ContactAvatarPreview.vue`,
  `${root}/routes/dashboard/conversation/contact/ContactForm.vue`, `${root}/routes/dashboard/settings/settings.routes.js`,
  ...collect(`${root}/components/workspace`), ...collect(`${root}/routes/dashboard/settings/workspaceApps`),
  ...['en', 'es', 'pt', 'pt_BR'].map(locale => `${root}/i18n/locale/${locale}/index.js`),
];
for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  const source = file.endsWith('.vue') ? text.match(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/)?.[1] : text;
  if (!source) throw new Error(`Missing script: ${file}`);
  new vm.SourceTextModule(source, { identifier: file });
}
console.log(`JavaScript syntax OK: ${files.length} modules/script blocks`);
