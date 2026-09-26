import { frontendURL } from 'dashboard/helper/URLHelper';

export default {
  routes: [{
    path: frontendURL('accounts/:accountId/settings/workspace-apps'),
    component: () => import('../SettingsWrapper.vue'),
    props: { keepAlive: false },
    children: [{
      path: '', name: 'workspace_apps_settings',
      component: () => import('./Index.vue'),
      meta: { permissions: ['administrator'] },
    }],
  }],
};
