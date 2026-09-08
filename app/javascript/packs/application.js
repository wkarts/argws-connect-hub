import Vue from 'vue';
import VueI18n from 'vue-i18n';
import VueRouter from 'vue-router';
import axios from 'axios';
// Global Components
import hljs from 'highlight.js';
import Multiselect from 'vue-multiselect';
import VueFormulate from '@braid/vue-formulate';
import HubSwitch from 'components/ui/Switch';
import HubWizard from 'components/ui/Wizard';
import { sync } from 'vuex-router-sync';
import VTooltip from 'v-tooltip';
import HubUiKit from '../dashboard/components';
import App from '../dashboard/App';
import i18n from '../dashboard/i18n';
import createAxios from '../dashboard/helper/APIHelper';
import { emitter } from '../shared/helpers/mitt';

import commonHelpers, { isJSONValid } from '../dashboard/helper/commons';
import router, { initalizeRouter } from '../dashboard/routes';
import store from '../dashboard/store';
import constants from 'dashboard/constants/globals';
import 'vue-easytable/libs/theme-default/index.css';
import {
  initializeHubEvents,
} from '../dashboard/helper/scriptHelpers';
import FluentIcon from 'shared/components/FluentIcon/DashboardIcon';
import VueDOMPurifyHTML from 'vue-dompurify-html';
import { domPurifyConfig } from '../shared/helpers/HTMLSanitizer';
import resizeDirective from '../dashboard/helper/directives/resize.js';
import { directive as onClickaway } from 'vue-clickaway';

Vue.config.env = process.env;


Vue.use(VueDOMPurifyHTML, domPurifyConfig);
Vue.use(VueRouter);
Vue.use(VueI18n);
Vue.use(HubUiKit);
Vue.use(VueFormulate, {
  rules: {
    JSON: ({ value }) => isJSONValid(value),
  },
});
Vue.use(VTooltip, {
  defaultHtml: false,
});
Vue.use(hljs.vuePlugin);
Vue.component('multiselect', Multiselect);
Vue.component('hub-switch', HubSwitch);
Vue.component('hub-wizard', HubWizard);
Vue.component('fluent-icon', FluentIcon);

Vue.directive('resize', resizeDirective);
Vue.directive('on-clickaway', onClickaway);
const i18nConfig = new VueI18n({
  locale: 'en',
  messages: i18n,
});

sync(store, router);
// load common helpers into js
commonHelpers();

window.HubConstants = constants;
window.axios = createAxios(axios);
Vue.prototype.$emitter = emitter;

initializeHubEvents();
initalizeRouter();

window.onload = () => {
  window.HUB = new Vue({
    router,
    store,
    i18n: i18nConfig,
    components: { App },
    template: '<App/>',
  }).$mount('#app');
};

window.addEventListener('load', () => {
  window.playAudioAlert = () => {};
});
