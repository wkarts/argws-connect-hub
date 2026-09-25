// Validate every affected Vue template using the project's own Vue 2 compiler.
const fs = require('node:fs');
const compiler = require('vue-template-compiler');
const root = 'app/javascript/dashboard/';
const files = [
  'App.vue', 'components/layout/Sidebar.vue',
  'components/layout/sidebarComponents/Primary.vue',
  'components/layout/sidebarComponents/PrimaryNavItem.vue',
  'components/widgets/forms/AvatarUploader.vue',
  'modules/contact/components/ContactAvatarPreview.vue',
  'routes/dashboard/conversation/contact/ContactForm.vue',
  'routes/dashboard/settings/workspaceApps/Index.vue',
  ...fs.readdirSync(`${root}components/workspace`).filter(name => name.endsWith('.vue')).map(name => `components/workspace/${name}`),
];
for (const file of files) {
  const descriptor = compiler.parseComponent(fs.readFileSync(`${root}${file}`, 'utf8'));
  const result = compiler.compile(descriptor.template.content);
  if (result.errors.length) throw new Error(`${file}: ${result.errors.join('; ')}`);
}
console.log(`Vue 2 templates OK: ${files.length} files`);
