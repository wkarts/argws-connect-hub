<script>
import api from 'dashboard/api/workspaceApps';
import { safeDiagnosticUrl } from 'dashboard/helper/workspacePresentation.mjs';

export default {
  props: { app: { type: Object, required: true }, accountId: { type: Number, required: true }, localFailure: { type: Object, default: null } },
  data() { return { busy: false, result: null, failed: false, copied: false, disposed: false, hubOrigin: window.location.origin }; },
  computed: {
    destination() { return safeDiagnosticUrl(this.app.url); },
    isAdmin() { return this.$store?.getters.getCurrentRole === 'administrator'; },
    settingsPath() { return `/app/accounts/${this.accountId}/settings/workspace-apps`; },
    suggestion() { return `Content-Security-Policy: frame-ancestors 'self' ${this.hubOrigin};`; },
    resultLabel() {
      if (!this.result) return '';
      if (this.result.code !== 'headers_checked') return this.$t(`WORKSPACE_APPS.DIAGNOSTIC_CODES.${this.result.code}`);
      return this.$t(`WORKSPACE_APPS.DIAGNOSTIC_VERDICTS.${this.result.verdict}`);
    },
    report() { return JSON.stringify({ application: this.app.name, destination: this.destination, hub_origin: this.hubOrigin, browser_policy: this.localFailure, probe: this.result }, null, 2); },
  },
  mounted() { this.run(); this.$nextTick(() => this.$refs.close?.focus()); },
  beforeDestroy() { this.disposed = true; },
  methods: {
    async run() {
      if (this.busy) return;
      this.busy = true; this.failed = false; this.copied = false;
      try {
        const { data } = await api.diagnose(this.accountId, this.app.id);
        if (!this.disposed) this.result = data;
      } catch (_) { if (!this.disposed) this.failed = true; }
      finally { if (!this.disposed) this.busy = false; }
    },
    async copy() {
      try { await navigator.clipboard.writeText(this.report); this.copied = true; }
      catch (_) { this.$refs.details.open = true; this.$nextTick(() => { this.$refs.report.focus(); this.$refs.report.select(); }); }
    },
  },
};
</script>

<template>
  <div class="workspace-diagnostics" role="dialog" aria-modal="false" :aria-label="$t('WORKSPACE_APPS.DIAGNOSE')" @keydown.esc.stop="$emit('close')">
    <div class="workspace-diagnostics__panel">
      <div class="workspace-diagnostics__heading"><h2>{{ $t('WORKSPACE_APPS.DIAGNOSE') }}</h2><button ref="close" type="button" :aria-label="$t('WORKSPACE_APPS.DISMISS')" @click="$emit('close')"><fluent-icon icon="dismiss" size="20" /></button></div>
      <p class="workspace-diagnostics__notice">{{ $t('WORKSPACE_APPS.DIAG_SCOPE') }}</p>
      <dl><dt>{{ $t('WORKSPACE_APPS.DIAG_DESTINATION') }}</dt><dd>{{ destination }}</dd><dt>{{ $t('WORKSPACE_APPS.DIAG_ORIGIN') }}</dt><dd>{{ hubOrigin }}</dd></dl>
      <p v-if="localFailure" role="alert">{{ $t('WORKSPACE_APPS.LOCAL_POLICY_ERROR') }} <code>{{ localFailure.directive }}</code> — {{ localFailure.origin }}</p>
      <p v-if="busy" role="status">{{ $t('WORKSPACE_APPS.DIAG_LOADING') }}</p>
      <p v-if="failed" role="alert">{{ $t('WORKSPACE_APPS.DIAG_FAILED') }}</p>
      <template v-if="result">
        <p role="status"><strong>{{ resultLabel }}</strong><span v-if="result.status"> — HTTP {{ result.status }}</span></p>
        <p v-if="result.hub_origin !== hubOrigin">{{ $t('WORKSPACE_APPS.DIAG_ORIGIN_MISMATCH') }} <code>{{ result.hub_origin }}</code></p>
        <pre v-if="result.frame_ancestors && result.frame_ancestors.length">{{ result.frame_ancestors.join('\n') }}</pre>
        <pre v-if="result.x_frame_options">X-Frame-Options: {{ result.x_frame_options }}</pre>
        <p v-if="result.report_only && result.report_only.length">{{ $t('WORKSPACE_APPS.DIAG_REPORT_ONLY') }}</p>
        <div v-for="(step, index) in result.steps" :key="index" class="workspace-diagnostics__step">HTTP {{ step.status }} · {{ step.url }}</div>
      </template>
      <h3>{{ $t('WORKSPACE_APPS.DIAG_FIX_TITLE') }}</h3>
      <p>{{ $t('WORKSPACE_APPS.DIAG_FIX_POLICY') }}</p>
      <pre>{{ suggestion }}</pre>
      <p>{{ $t('WORKSPACE_APPS.DIAG_FIX_KEEP') }}</p>
      <p>{{ $t('WORKSPACE_APPS.DIAG_FIX_NETWORK') }}</p>
      <p>{{ $t('WORKSPACE_APPS.DIAG_BROWSER_CONSOLE') }}</p>
      <details ref="details"><summary>{{ $t('WORKSPACE_APPS.DIAG_TECHNICAL') }}</summary><textarea ref="report" readonly :value="report" :aria-label="$t('WORKSPACE_APPS.DIAG_TECHNICAL')" /></details>
      <div class="workspace-diagnostics__actions">
        <hub-button type="button" :disabled="busy" @click="run">{{ $t('WORKSPACE_APPS.DIAG_RECHECK') }}</hub-button>
        <hub-button type="button" variant="hollow" @click="copy">{{ $t(copied ? 'WORKSPACE_APPS.DIAG_COPIED' : 'WORKSPACE_APPS.DIAG_COPY') }}</hub-button>
        <a :href="app.url" target="_blank" rel="noopener noreferrer" referrerpolicy="no-referrer">{{ $t('WORKSPACE_APPS.OPEN_EXTERNAL') }}</a>
        <router-link v-if="isAdmin" :to="settingsPath">{{ $t('WORKSPACE_APPS.EDIT') }}</router-link>
      </div>
    </div>
  </div>
</template>

<style scoped>
.workspace-diagnostics { position: absolute; inset: 0; z-index: 4; padding: 46px 16px 16px; overflow: auto; background: rgb(15 23 42 / .15); }
.workspace-diagnostics__panel { max-width: 760px; margin: 0 auto; padding: 20px; border: 1px solid #e2e8f0; border-radius: 10px; background: white; color: #334155; box-shadow: 0 8px 28px rgb(15 23 42 / .12); font-size: 13px; }
.workspace-diagnostics__heading { display: flex; align-items: center; justify-content: space-between; }
.workspace-diagnostics h2 { font-size: 16px; margin: 0; }
.workspace-diagnostics h3 { font-size: 14px; margin-top: 18px; }
.workspace-diagnostics p { font-size: 13px; line-height: 1.6; margin: 12px 0; }
.workspace-diagnostics__heading button { background: transparent; border: 0; padding: 4px; cursor: pointer; color: inherit; }
.workspace-diagnostics dt { font-weight: 600; }
.workspace-diagnostics dd, .workspace-diagnostics__step { margin: 0 0 8px; overflow-wrap: anywhere; }
.workspace-diagnostics pre, .workspace-diagnostics textarea { width: 100%; white-space: pre-wrap; overflow-wrap: anywhere; padding: 10px; background: #f8fafc; border-radius: 5px; color: #334155; font-size: 12px; }
.workspace-diagnostics textarea { min-height: 150px; }
.workspace-diagnostics__actions { display: flex; align-items: center; flex-wrap: wrap; gap: 10px; margin-top: 16px; }
.workspace-diagnostics__notice { color: #64748b; }
.dark .workspace-diagnostics__panel { background: #0f172a; color: #e2e8f0; border-color: #334155; }
.dark .workspace-diagnostics pre, .dark .workspace-diagnostics textarea { background: #1e293b; color: #e2e8f0; }
</style>
