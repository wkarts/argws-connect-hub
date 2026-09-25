<script>
import api from 'dashboard/api/workspaceApps';
import WorkspaceIcon from './WorkspaceIcon.vue';
import { submitApplicationLogin } from 'dashboard/helper/workspaceApps.mjs';

export default {
  components: { WorkspaceIcon },
  props: {
    app: { type: Object, required: true },
    accountId: { type: Number, required: true },
  },
  data() {
    return {
      frameName: `hub-workspace-${this.accountId}-${this.app.id}-${Math.random().toString(36).slice(2)}`,
      frameReady: this.app.auth_mode === 'session',
      initialSrc: this.app.auth_mode === 'session' ? this.app.url : 'about:blank',
      showLogin: false, busy: false, disposed: false, username: '', password: '',
      remember: false, autoLogin: false, saved: false, error: '', showHelp: true,
    };
  },
  computed: {
    destination() { return new URL(this.app.login_url || this.app.url).host; },
  },
  mounted() { if (this.app.auth_mode === 'form_post') this.prepareLogin(); },
  beforeDestroy() { this.disposed = true; this.password = ''; this.username = ''; },
  methods: {
    async prepareLogin() {
      this.busy = true;
      try {
        const { data } = await api.credential(this.accountId, this.app.id);
        if (this.disposed) return;
        this.saved = data.saved;
        this.username = data.username || '';
        if (data.saved && data.auto_login) { await this.login(true); return; }
        this.showLogin = true;
      } catch (_) {
        if (!this.disposed) { this.showLogin = true; this.error = this.$t('WORKSPACE_APPS.CREDENTIAL_ERROR'); }
      } finally { if (!this.disposed) this.busy = false; }
    },
    async login(useSaved = false) {
      this.error = '';
      this.busy = true;
      const input = { integration_revision: this.app.integration_revision };
      if (!useSaved) input.workspace_credentials = { username: this.username, password: this.password, remember: this.remember, auto_login: this.remember && this.autoLogin };
      let payload;
      try {
        const { data } = await api.launch(this.accountId, this.app.id, input);
        payload = data;
        if (this.disposed) return;
        this.frameReady = true;
        await this.$nextTick();
        if (this.disposed) return;
        submitApplicationLogin(document, this.$refs.frame, this.app, payload, window.location.origin);
        this.saved = this.saved || this.remember;
        this.showLogin = false;
      } catch (_) {
        if (!this.disposed) { this.error = this.$t('WORKSPACE_APPS.LOGIN_ERROR'); this.showLogin = true; }
      } finally {
        if (payload) { payload.password = ''; payload.username = ''; }
        if (input.workspace_credentials) input.workspace_credentials.password = '';
        this.password = '';
        if (!this.disposed) this.busy = false;
      }
    },
    nativeLogin() {
      this.initialSrc = this.app.url;
      this.frameReady = true;
      this.showLogin = false;
      this.password = '';
      this.error = '';
    },
    async forget() {
      this.busy = true;
      try {
        await api.forgetCredential(this.accountId, this.app.id);
        if (!this.disposed) { this.saved = false; this.password = ''; this.remember = false; this.autoLogin = false; }
      } catch (_) { if (!this.disposed) this.error = this.$t('WORKSPACE_APPS.CREDENTIAL_ERROR'); }
      finally { if (!this.disposed) this.busy = false; }
    },
  },
};
</script>

<template>
  <section class="workspace-frame" :aria-label="app.name">
    <header class="workspace-frame__header">
      <button type="button" class="workspace-frame__action" :aria-label="$t('WORKSPACE_APPS.BACK_TO_HUB')" :title="$t('WORKSPACE_APPS.BACK_TO_HUB')" @click="$store.commit('workspaceApps/deactivate')"><fluent-icon icon="chevron-left" size="20" /></button>
      <WorkspaceIcon :app="app" />
      <strong class="workspace-frame__title">{{ app.name }}</strong>
      <button v-if="app.auth_mode === 'form_post'" type="button" class="workspace-frame__action" :aria-label="$t('WORKSPACE_APPS.MY_LOGIN')" :title="$t('WORKSPACE_APPS.MY_LOGIN')" @click="showLogin = true"><fluent-icon icon="key" size="20" /></button>
      <button type="button" class="workspace-frame__action" :aria-label="$t('WORKSPACE_APPS.RELOAD')" :title="$t('WORKSPACE_APPS.RELOAD')" @click="$emit('confirmAction', { action: 'reload', id: app.id })"><fluent-icon icon="arrow-clockwise" size="20" /></button>
      <a :href="app.url" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer" class="workspace-frame__action" :aria-label="$t('WORKSPACE_APPS.OPEN_EXTERNAL')" :title="$t('WORKSPACE_APPS.OPEN_EXTERNAL')"><fluent-icon icon="open" size="20" /></a>
      <button type="button" class="workspace-frame__action" :aria-label="$t('WORKSPACE_APPS.CLOSE_APP')" :title="$t('WORKSPACE_APPS.CLOSE_APP')" @click="$emit('confirmAction', { action: 'close', id: app.id })"><fluent-icon icon="dismiss" size="20" /></button>
    </header>
    <div v-if="showHelp" class="workspace-frame__help">
      <span>{{ $t('WORKSPACE_APPS.EMBED_HELP') }}</span>
      <button type="button" :aria-label="$t('WORKSPACE_APPS.DISMISS')" @click="showHelp = false"><fluent-icon icon="dismiss" size="14" /></button>
    </div>
    <div class="workspace-frame__body">
      <iframe
        v-if="frameReady"
        ref="frame"
        :name="frameName"
        :src="initialSrc"
        :title="app.name"
        class="workspace-frame__iframe"
        sandbox="allow-forms allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-downloads allow-modals"
        allow="camera 'none'; microphone 'none'; geolocation 'none'; payment 'none'"
        referrerpolicy="no-referrer"
      />
      <div v-if="!frameReady && !showLogin" class="workspace-frame__loading" role="status">{{ $t('WORKSPACE_APPS.LOADING') }}</div>
      <div v-if="showLogin" class="workspace-frame__login-overlay">
        <form class="workspace-frame__login" @submit.prevent="login(false)">
          <div class="workspace-frame__login-heading">
            <h2>{{ $t('WORKSPACE_APPS.MY_LOGIN') }}</h2>
            <button v-if="frameReady" type="button" class="workspace-frame__action" :aria-label="$t('WORKSPACE_APPS.DISMISS')" @click="showLogin = false; password = ''"><fluent-icon icon="dismiss" size="18" /></button>
          </div>
          <strong>{{ app.name }}</strong>
          <p class="workspace-frame__destination">{{ destination }}</p>
          <p>{{ $t('WORKSPACE_APPS.CREDENTIAL_NOTICE') }}</p>
          <label>{{ $t('WORKSPACE_APPS.USERNAME') }}<input v-model="username" type="text" autocomplete="off" maxlength="512" required :disabled="busy" /></label>
          <label>{{ $t('WORKSPACE_APPS.PASSWORD') }}<input v-model="password" type="password" autocomplete="off" maxlength="4096" required :disabled="busy" /></label>
          <label v-if="app.allow_saved_credentials" class="workspace-frame__checkbox"><input v-model="remember" type="checkbox" :disabled="busy" />{{ $t('WORKSPACE_APPS.REMEMBER') }}</label>
          <label v-if="app.allow_auto_login && remember" class="workspace-frame__checkbox"><input v-model="autoLogin" type="checkbox" :disabled="busy" />{{ $t('WORKSPACE_APPS.AUTO_LOGIN') }}</label>
          <p v-if="error" class="workspace-frame__error" role="alert">{{ error }}</p>
          <div class="workspace-frame__login-actions">
            <hub-button type="submit" :disabled="busy">{{ $t('WORKSPACE_APPS.SIGN_IN') }}</hub-button>
            <hub-button v-if="saved" type="button" variant="hollow" :disabled="busy" @click="login(true)">{{ $t('WORKSPACE_APPS.USE_SAVED') }}</hub-button>
          </div>
          <button type="button" class="workspace-frame__text-action" :disabled="busy" @click="nativeLogin">{{ $t('WORKSPACE_APPS.NATIVE_LOGIN') }}</button>
          <button v-if="saved" type="button" class="workspace-frame__text-action" :disabled="busy" @click="forget">{{ $t('WORKSPACE_APPS.FORGET') }}</button>
          <small>{{ $t('WORKSPACE_APPS.POST_HELP') }}</small>
        </form>
      </div>
    </div>
  </section>
</template>

<style scoped>
.workspace-frame { height: 100%; width: 100%; display: flex; flex-direction: column; background: white; color: #0f172a; }
.workspace-frame__header { display: flex; align-items: center; gap: .65rem; min-height: 3.5rem; flex-shrink: 0; padding: .4rem .8rem; border-bottom: 1px solid #e2e8f0; }
.workspace-frame__title { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: .95rem; }
.workspace-frame__action { display: inline-flex; align-items: center; justify-content: center; width: 2.2rem; height: 2.2rem; flex-shrink: 0; padding: 0; background: transparent; color: #475569; border: 0; border-radius: .5rem; cursor: pointer; }
.workspace-frame__action:hover { background: #f1f5f9; }
.workspace-frame__action:focus-visible { outline: 2px solid #3b82f6; }
.workspace-frame__help { display: flex; align-items: center; justify-content: space-between; gap: .7rem; padding: .4rem 1rem; font-size: .75rem; color: #64748b; background: #f8fafc; }
.workspace-frame__help button { display: flex; padding: 0; background: transparent; border: 0; color: inherit; cursor: pointer; }
.workspace-frame__body { flex: 1; min-height: 0; position: relative; }
.workspace-frame__iframe { width: 100%; height: 100%; border: 0; display: block; background: white; }
.workspace-frame__loading { display: grid; place-items: center; height: 100%; }
.workspace-frame__login-overlay { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; overflow: auto; padding: 1.5rem; background: rgb(15 23 42 / .25); }
.workspace-frame__login { width: min(100%, 30rem); max-height: 100%; overflow: auto; padding: 1.5rem; border: 1px solid #e2e8f0; border-radius: 1rem; background: white; box-shadow: 0 12px 36px rgb(15 23 42 / .12); }
.workspace-frame__login-heading { display: flex; align-items: center; justify-content: space-between; }
.workspace-frame__login-heading h2 { font-size: 1.15rem; margin: 0 0 1rem; }
.workspace-frame__destination { color: #2563eb; overflow-wrap: anywhere; }
.workspace-frame__login p, .workspace-frame__login small { font-size: .85rem; color: #64748b; }
.workspace-frame__checkbox { display: flex; align-items: center; gap: .65rem; font-size: .85rem; }
.workspace-frame__checkbox input { margin: 0; }
.workspace-frame__login-actions { display: flex; flex-wrap: wrap; gap: .5rem; margin: 1rem 0; }
.workspace-frame__text-action { display: block; background: none; border: 0; padding: .4rem 0; font-size: .85rem; color: #2563eb; cursor: pointer; }
.workspace-frame__login .workspace-frame__error { color: #b91c1c; }
.dark .workspace-frame, .dark .workspace-frame__login { background: #0f172a; color: #e2e8f0; border-color: #334155; }
.dark .workspace-frame__header { border-color: #334155; }
.dark .workspace-frame__help { background: #1e293b; color: #cbd5e1; }
.dark .workspace-frame__action { color: #cbd5e1; }
.dark .workspace-frame__action:hover { background: #1e293b; }
@media (max-width: 640px) { .workspace-frame__header { gap: .2rem; padding-inline: .25rem; } .workspace-frame__login-overlay { padding: .5rem; } }
</style>
