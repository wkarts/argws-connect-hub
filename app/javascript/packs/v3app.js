import Vue from 'vue';
import VueI18n from 'vue-i18n';
import VueRouter from 'vue-router';
import i18n from 'dashboard/i18n';
import {
  initializeHubEvents,
} from 'dashboard/helper/scriptHelpers';
import App from '../v3/App.vue';
import router, { initalizeRouter } from '../v3/views/index';
import store from '../v3/store';
import FluentIcon from 'shared/components/FluentIcon/DashboardIcon';
import { emitter } from '../shared/helpers/mitt';

Vue.config.env = process.env;


Vue.use(VueRouter);
Vue.use(VueI18n);
Vue.prototype.$emitter = emitter;
Vue.component('fluent-icon', FluentIcon);

const i18nConfig = new VueI18n({ locale: 'en', messages: i18n });

initializeHubEvents();
initalizeRouter();
window.onload = () => {
  new Vue({
    router,
    store,
    i18n: i18nConfig,
    components: { App },
    template: '<App/>',
  }).$mount('#app');
};
