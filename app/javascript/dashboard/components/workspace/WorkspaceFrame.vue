<script>
import api from 'dashboard/api/workspaceApps';
import WorkspaceToolbar from './WorkspaceToolbar.vue';
import WorkspaceDiagnostics from './WorkspaceDiagnostics.vue';
import { NAVIGATION_CHANNEL, navigationMessage, navigationNonce } from 'dashboard/helper/workspaceNavigation.mjs';
import { submitApplicationLogin } from 'dashboard/helper/workspaceApps.mjs';

export default {
  components: { WorkspaceToolbar, WorkspaceDiagnostics },
  props: {
    app: { type: Object, required: true },
    active: { type: Boolean, default: true },
    scope: { type: String, default: '' },
    accountId: { type: Number, required: true },
  },
  data() {
    return {
      frameName: `hub-workspace-${this.accountId}-${this.app.id}-${Math.random().toString(36).slice(2)}`,
      frameReady: this.app.auth_mode === 'session',
      initialSrc: this.app.auth_mode === 'session' ? this.app.url : 'about:blank',
      showLogin: false, busy: false, disposed: false, username: '', password: '',
      remember: false, autoLogin: false, saved: false, error: '', pinned: false, showDiagnostics: false,
      navigation: { ready: false, back: false, forward: false }, navigationToken: '',
      slow: false, offline: !navigator.onLine, localFailure: null,
    };
  },
  computed: {
    destination() { return new URL(this.app.login_url || this.app.url).host; },
  },
  mounted() {
    window.addEventListener('message', this.receiveNavigation);
    window.addEventListener('online', this.networkChanged);
    window.addEventListener('offline', this.networkChanged);
    document.addEventListener('securitypolicyviolation', this.policyViolation);
    if (this.app.auth_mode === 'form_post') this.prepareLogin();
    else this.startLoadTimer();
  },
  beforeDestroy() {
    this.disposed = true; this.password = ''; this.username = '';
    clearTimeout(this.loadTimer);
    window.removeEventListener('message', this.receiveNavigation);
    window.removeEventListener('online', this.networkChanged);
    window.removeEventListener('offline', this.networkChanged);
    document.removeEventListener('securitypolicyviolation', this.policyViolation);
  },
  methods: {
    startLoadTimer() {
      clearTimeout(this.loadTimer); this.slow = false;
      this.loadTimer = setTimeout(() => { if (!this.disposed) this.slow = true; }, 12000);
    },
    frameLoaded() {
      // load is not proof of a successful foreign document. Never claim success here.
      clearTimeout(this.loadTimer); this.slow = false;
      this.navigation = { ready: false, back: false, forward: false };
      this.navigationToken = navigationNonce();
      this.$refs.frame?.contentWindow?.postMessage({ channel: NAVIGATION_CHANNEL, type: 'hello', nonce: this.navigationToken }, new URL(this.app.url).origin);
    },
    receiveNavigation(event) {
      if (!navigationMessage(event, this.$refs.frame, new URL(this.app.url).origin, this.navigationToken)) return;
      this.navigation = { ready: event.data.supported, back: event.data.back, forward: event.data.forward };
    },
    navigate(direction) {
      if (!this.navigation.ready || !['back', 'forward'].includes(direction) || !this.navigation[direction]) return;
      this.$refs.frame?.contentWindow?.postMessage({ channel: NAVIGATION_CHANNEL, type: 'navigate', nonce: this.navigationToken, direction }, new URL(this.app.url).origin);
    },
    networkChanged() { this.offline = !navigator.onLine; },
    policyViolation(event) {
      if (event.disposition !== 'enforce' || !['frame-src', 'child-src'].includes(event.effectiveDirective)) return;
      try {
        if (new URL(event.blockedURI).origin !== new URL(this.app.url).origin) return;
        this.localFailure = { code: 'hub_frame_policy', directive: event.effectiveDirective, origin: new URL(event.blockedURI).origin };
      } catch (_) { /* A redacted browser event cannot identify this application. */ }
    },
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
        this.startLoadTimer();
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
      this.startLoadTimer();
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
  <section class="workspace-frame" :class="{ 'workspace-frame--pinned': pinned }" :aria-label="app.name">
    <WorkspaceToolbar :app="app" :scope="scope" :active="active" :force-visible="showLogin || showDiagnostics" :navigation="navigation"
      @pin="pinned = $event" @hub="$store.commit('workspaceApps/deactivate')" @navigate="navigate" @login="showLogin = true" @diagnose="showDiagnostics = true"
      @reload="$emit('confirmAction', { action: 'reload', id: app.id })" @close="$emit('confirmAction', { action: 'close', id: app.id })" />
    <div class="workspace-frame__body">
      <iframe
        v-if="frameReady"
        ref="frame"
        :name="frameName"
        :src="initialSrc"
        :title="app.name"
        class="workspace-frame__iframe"
        @load="frameLoaded"
        sandbox="allow-forms allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-downloads allow-modals"
        allow="camera 'none'; microphone 'none'; geolocation 'none'; payment 'none'"
        referrerpolicy="no-referrer"
      />
      <div v-if="offline || slow || localFailure" class="workspace-frame__notice" role="status">
        <span>{{ $t(offline ? 'WORKSPACE_APPS.NETWORK_OFFLINE' : localFailure ? 'WORKSPACE_APPS.LOCAL_POLICY_ERROR' : 'WORKSPACE_APPS.LOAD_UNCONFIRMED') }}</span>
        <button type="button" @click="showDiagnostics = true">{{ $t('WORKSPACE_APPS.DIAGNOSE') }}</button>
      </div>
      <WorkspaceDiagnostics v-if="showDiagnostics" :app="app" :account-id="accountId" :local-failure="localFailure" @close="showDiagnostics = false" />
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
.workspace-frame { position: relative; height: 100%; width: 100%; display: flex; flex-direction: column; background: white; color: #0f172a; }
.workspace-frame__action { display: inline-flex; align-items: center; justify-content: center; width: 2.2rem; height: 2.2rem; flex-shrink: 0; padding: 0; background: transparent; color: #475569; border: 0; border-radius: .5rem; cursor: pointer; }
.workspace-frame__action:hover { background: #f1f5f9; }
.workspace-frame__action:focus-visible { outline: 2px solid #3b82f6; }
.workspace-frame--pinned { padding-top: 38px; box-sizing: border-box; }
.workspace-frame__body { flex: 1; min-height: 0; position: relative; }
.workspace-frame__notice { position: absolute; bottom: 12px; inset-inline: 12px; z-index: 1; display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 8px 12px; border: 1px solid #cbd5e1; border-radius: 6px; background: #f8fafc; color: #475569; font-size: 12px; }
.workspace-frame__notice button { border: 0; padding: 4px; background: transparent; color: #2563eb; cursor: pointer; }
.workspace-frame__iframe { width: 100%; height: 100%; border: 0; display: block; background: white; }
.workspace-frame__loading { display: grid; place-items: center; height: 100%; }
.workspace-frame__login-overlay { position: absolute; z-index: 2; inset: 0; display: flex; align-items: center; justify-content: center; overflow: auto; padding: 1.5rem; background: rgb(15 23 42 / .25); }
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
.dark .workspace-frame__action { color: #cbd5e1; }
.dark .workspace-frame__action:hover { background: #1e293b; }
@media (max-width: 640px) { .workspace-frame__login-overlay { padding: .5rem; } }
</style>
