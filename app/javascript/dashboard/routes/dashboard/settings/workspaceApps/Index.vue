<script>
import api from 'dashboard/api/workspaceApps';
import WorkspaceIcon from 'dashboard/components/workspace/WorkspaceIcon.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import { useAlert } from 'dashboard/composables';

const emptyForm = () => ({
  name: '', url: '', icon_name: 'globe', enabled: true, position: 0,
  launch_mode: 'embedded', auth_mode: 'session', login_url: '', username_field: 'username',
  password_field: 'password', allow_saved_credentials: false, allow_auto_login: false,
  access_mode: 'everyone', allowed_user_ids: [],
});
const EDITABLE = Object.keys(emptyForm());

export default {
  components: { WorkspaceIcon, SettingsLayout, BaseSettingsHeader },
  data() {
    return {
      apps: [], members: [], loading: false, saving: false, error: '', showForm: false, editingId: null,
      form: emptyForm(), iconFile: null, iconPreview: '', removeIcon: false, pendingDelete: null,
      icons: ['globe', 'briefcase', 'calendar', 'mail', 'chat-multiple', 'people', 'document', 'key', 'settings'],
      selectedUsers: [], disposed: false, requestSequence: 0,
    };
  },
  computed: {
    accountId() { return Number(this.$store.getters.getCurrentAccountId); },
    agents() { return this.members; },
    previewApp() { return { ...this.form, icon_url: this.removeIcon ? null : this.iconPreview }; },
  },
  watch: {
    accountId: { immediate: true, handler() { this.saving = false; this.closeForm(); this.editingId = null; this.form = emptyForm(); this.pendingDelete = null; this.apps = []; this.members = []; this.load(); } },
    'form.launch_mode'(mode) { if (mode === 'external') this.form.auth_mode = 'session'; },
    'form.auth_mode'(mode) { if (mode === 'session') { this.form.allow_saved_credentials = false; this.form.allow_auto_login = false; } },
    'form.allow_saved_credentials'(allowed) { if (!allowed) this.form.allow_auto_login = false; },
  },
  beforeDestroy() { this.disposed = true; this.releasePreview(); },
  methods: {
    async load() {
      const accountId = this.accountId;
      const sequence = ++this.requestSequence;
      this.loading = true;
      this.error = '';
      try {
        const [catalog, members] = await Promise.all([api.manage(accountId), api.members(accountId)]);
        if (!this.disposed && accountId === this.accountId && sequence === this.requestSequence) {
          this.apps = catalog.data;
          this.members = members.data;
        }
      } catch (_) {
        if (!this.disposed && accountId === this.accountId) this.error = this.$t('WORKSPACE_APPS.LOAD_ERROR');
      } finally { if (!this.disposed && accountId === this.accountId && sequence === this.requestSequence) this.loading = false; }
    },
    releasePreview() { if (this.iconPreview?.startsWith('blob:')) URL.revokeObjectURL(this.iconPreview); },
    closeForm() {
      if (this.saving) return;
      this.releasePreview(); this.showForm = false; this.iconFile = null; this.iconPreview = ''; this.error = '';
    },
    edit(app = null) {
      this.releasePreview();
      this.editingId = app?.id || null;
      this.form = Object.assign(emptyForm(), ...EDITABLE.filter(key => app && key in app).map(key => ({ [key]: app[key] })));
      this.selectedUsers = this.form.allowed_user_ids.map(id => this.agents.find(agent => agent.id === id) || { id, name: `#${id}` });
      this.iconFile = null; this.iconPreview = app?.icon_url || ''; this.removeIcon = false; this.error = ''; this.showForm = true;
    },
    pickIcon(event) {
      const file = event.target.files[0];
      if (!file) return;
      if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 1024 * 1024) {
        this.error = this.$t('WORKSPACE_APPS.ICON_ERROR'); event.target.value = ''; return;
      }
      this.releasePreview(); this.iconFile = file; this.iconPreview = URL.createObjectURL(file); this.removeIcon = false; this.error = '';
    },
    clearIcon() { this.releasePreview(); this.iconFile = null; this.iconPreview = ''; this.removeIcon = true; },
    payload() {
      const values = { ...this.form, allowed_user_ids: this.form.access_mode === 'selected' ? this.selectedUsers.map(user => Number(user.id)) : [], remove_icon: this.removeIcon };
      if (!this.iconFile) return { workspace_app: values };
      const data = new FormData();
      Object.entries(values).forEach(([key, value]) => {
        if (Array.isArray(value)) (value.length ? value : ['']).forEach(id => data.append(`workspace_app[${key}][]`, id));
        else data.append(`workspace_app[${key}]`, value ?? '');
      });
      data.append('workspace_app[icon]', this.iconFile);
      return data;
    },
    async save() {
      const accountId = this.accountId;
      this.saving = true; this.error = '';
      try {
        if (this.editingId) await api.update(accountId, this.editingId, this.payload());
        else await api.create(accountId, this.payload());
        if (this.disposed || accountId !== this.accountId) return;
        this.saving = false; this.closeForm(); await this.load();
        await this.$store.dispatch('workspaceApps/refresh');
        useAlert(this.$t('WORKSPACE_APPS.SAVED'));
      } catch (error) {
        if (!this.disposed && accountId === this.accountId) this.error = error.response?.data?.message || this.$t('WORKSPACE_APPS.SAVE_ERROR');
      } finally { if (!this.disposed) this.saving = false; }
    },
    async remove() {
      const accountId = this.accountId;
      const id = this.pendingDelete.id;
      this.saving = true;
      try {
        await api.remove(accountId, id);
        if (this.disposed || accountId !== this.accountId) return;
        this.pendingDelete = null; await this.load(); await this.$store.dispatch('workspaceApps/refresh');
      } catch (_) { if (!this.disposed && accountId === this.accountId) this.error = this.$t('WORKSPACE_APPS.SAVE_ERROR'); }
      finally { if (!this.disposed) this.saving = false; }
    },
  },
};
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="$t('WORKSPACE_APPS.LOADING')" :no-records-found="!apps.length" :no-records-message="$t('WORKSPACE_APPS.EMPTY')">
    <template #header>
      <BaseSettingsHeader :title="$t('WORKSPACE_APPS.TITLE')" :description="$t('WORKSPACE_APPS.DESCRIPTION')" icon-name="globe">
        <template #actions><hub-button type="button" icon="add" @click="edit()">{{ $t('WORKSPACE_APPS.ADD') }}</hub-button></template>
      </BaseSettingsHeader>
    </template>
    <template #preBody><p v-if="error && !showForm" class="workspace-settings__error" role="alert">{{ error }}</p></template>
    <template #body>
      <div class="workspace-settings__list">
        <article v-for="app in apps" :key="app.id" class="workspace-settings__row">
          <div class="workspace-settings__icon"><WorkspaceIcon :app="app" /></div>
          <div class="workspace-settings__identity"><strong>{{ app.name }}</strong><span>{{ app.url }}</span><small>{{ $t(`WORKSPACE_APPS.${app.launch_mode === 'embedded' ? 'EMBEDDED' : 'EXTERNAL'}`) }}</small></div>
          <span class="workspace-settings__status" :class="{ 'is-disabled': !app.enabled }">{{ $t(`WORKSPACE_APPS.${app.enabled ? 'ENABLED' : 'DISABLED'}`) }}</span>
          <hub-button type="button" variant="clear" icon="edit" :title="$t('WORKSPACE_APPS.EDIT')" :aria-label="$t('WORKSPACE_APPS.EDIT')" @click="edit(app)" />
          <hub-button type="button" variant="clear" color-scheme="alert" icon="delete" :title="$t('WORKSPACE_APPS.DELETE')" :aria-label="$t('WORKSPACE_APPS.DELETE')" @click="pendingDelete = app" />
        </article>
      </div>
    </template>
    <hub-modal :show="showForm" :on-close="closeForm" size="medium" :close-on-backdrop-click="!saving">
      <form class="workspace-settings__form" @submit.prevent="save">
        <h2>{{ $t(editingId ? 'WORKSPACE_APPS.EDIT' : 'WORKSPACE_APPS.ADD') }}</h2>
        <div class="workspace-settings__preview"><WorkspaceIcon :app="previewApp" /><strong>{{ form.name || $t('WORKSPACE_APPS.TITLE') }}</strong></div>
        <div class="workspace-settings__grid">
          <label>{{ $t('WORKSPACE_APPS.NAME') }}<input v-model.trim="form.name" type="text" required maxlength="120" :disabled="saving" /></label>
          <label>{{ $t('WORKSPACE_APPS.URL') }}<input v-model.trim="form.url" type="url" placeholder="https://" required maxlength="2048" :disabled="saving" /></label>
          <label>{{ $t('WORKSPACE_APPS.ICON') }}<select v-model="form.icon_name" :disabled="saving"><option v-for="icon in icons" :key="icon" :value="icon">{{ $t(`WORKSPACE_APPS.ICONS.${icon}`) }}</option></select></label>
          <label>{{ $t('WORKSPACE_APPS.ICON_UPLOAD') }}<input type="file" accept="image/png,image/jpeg,image/webp" :disabled="saving" @change="pickIcon" /><small>{{ $t('WORKSPACE_APPS.ICON_HELP') }}</small><button v-if="iconPreview" type="button" class="workspace-settings__link" @click="clearIcon">{{ $t('WORKSPACE_APPS.ICON_REMOVE') }}</button></label>
          <label>{{ $t('WORKSPACE_APPS.OPEN_MODE') }}<select v-model="form.launch_mode" :disabled="saving"><option value="embedded">{{ $t('WORKSPACE_APPS.EMBEDDED') }}</option><option value="external">{{ $t('WORKSPACE_APPS.EXTERNAL') }}</option></select></label>
          <label>{{ $t('WORKSPACE_APPS.ORDER') }}<input v-model.number="form.position" type="number" min="0" max="99999" required :disabled="saving" /></label>
        </div>
        <label class="workspace-settings__check"><input v-model="form.enabled" type="checkbox" :disabled="saving" />{{ $t('WORKSPACE_APPS.AVAILABLE') }}</label>
        <hr />
        <h3>{{ $t('WORKSPACE_APPS.ACCESS') }}</h3>
        <select v-model="form.access_mode" :aria-label="$t('WORKSPACE_APPS.ACCESS')" :disabled="saving"><option value="everyone">{{ $t('WORKSPACE_APPS.EVERYONE') }}</option><option value="administrators">{{ $t('WORKSPACE_APPS.ADMINS') }}</option><option value="selected">{{ $t('WORKSPACE_APPS.SELECTED_USERS') }}</option></select>
        <multiselect v-if="form.access_mode === 'selected'" v-model="selectedUsers" :options="agents" multiple label="name" track-by="id" :placeholder="$t('WORKSPACE_APPS.SELECT_USERS')" :disabled="saving" />
        <small>{{ $t('WORKSPACE_APPS.ACCESS_HELP') }}</small>
        <hr />
        <h3>{{ $t('WORKSPACE_APPS.AUTHENTICATION') }}</h3>
        <select v-model="form.auth_mode" :aria-label="$t('WORKSPACE_APPS.AUTHENTICATION')" :disabled="saving || form.launch_mode === 'external'"><option value="session">{{ $t('WORKSPACE_APPS.SESSION_AUTH') }}</option><option value="form_post">{{ $t('WORKSPACE_APPS.POST_AUTH') }}</option></select>
        <p class="workspace-settings__notice">{{ $t('WORKSPACE_APPS.AUTH_NOTICE') }}</p>
        <template v-if="form.auth_mode === 'form_post'">
          <label>{{ $t('WORKSPACE_APPS.LOGIN_URL') }}<input v-model.trim="form.login_url" type="url" placeholder="https://" required maxlength="2048" :disabled="saving" /></label>
          <div class="workspace-settings__grid">
            <label>{{ $t('WORKSPACE_APPS.USERNAME_FIELD') }}<input v-model.trim="form.username_field" type="text" required maxlength="80" :disabled="saving" /></label>
            <label>{{ $t('WORKSPACE_APPS.PASSWORD_FIELD') }}<input v-model.trim="form.password_field" type="text" required maxlength="80" :disabled="saving" /></label>
          </div>
          <label class="workspace-settings__check"><input v-model="form.allow_saved_credentials" type="checkbox" :disabled="saving" />{{ $t('WORKSPACE_APPS.ALLOW_SAVE') }}</label>
          <label class="workspace-settings__check"><input v-model="form.allow_auto_login" type="checkbox" :disabled="saving || !form.allow_saved_credentials" />{{ $t('WORKSPACE_APPS.ALLOW_AUTO') }}</label>
          <p class="workspace-settings__notice">{{ $t('WORKSPACE_APPS.POST_HELP') }}</p>
        </template>
        <p v-if="editingId" class="workspace-settings__notice">{{ $t('WORKSPACE_APPS.CHANGE_WARNING') }}</p>
        <p v-if="error" class="workspace-settings__error" role="alert">{{ error }}</p>
        <div class="workspace-settings__actions"><hub-button type="button" variant="hollow" :disabled="saving" @click="closeForm">{{ $t('WORKSPACE_APPS.CANCEL') }}</hub-button><hub-button type="submit" :disabled="saving">{{ $t('WORKSPACE_APPS.SAVE') }}</hub-button></div>
      </form>
    </hub-modal>
    <hub-modal :show="!!pendingDelete" :on-close="() => { if (!saving) pendingDelete = null; }" :close-on-backdrop-click="!saving">
      <div class="workspace-settings__delete"><h2>{{ $t('WORKSPACE_APPS.DELETE') }}</h2><p>{{ $t('WORKSPACE_APPS.DELETE_WARNING') }}</p><strong>{{ pendingDelete && pendingDelete.name }}</strong><div class="workspace-settings__actions"><hub-button type="button" variant="hollow" :disabled="saving" @click="pendingDelete = null">{{ $t('WORKSPACE_APPS.CANCEL') }}</hub-button><hub-button type="button" color-scheme="alert" :disabled="saving" @click="remove">{{ $t('WORKSPACE_APPS.DELETE') }}</hub-button></div></div>
    </hub-modal>
  </SettingsLayout>
</template>

<style scoped>
.workspace-settings__list { border: 1px solid #e2e8f0; border-radius: .75rem; overflow: hidden; }
.workspace-settings__row { display: flex; align-items: center; gap: .75rem; padding: 1rem; border-bottom: 1px solid #e2e8f0; }
.workspace-settings__row:last-child { border-bottom: 0; }
.workspace-settings__icon, .workspace-settings__preview { display: flex; align-items: center; justify-content: center; gap: .75rem; padding: .65rem; background: #f8fafc; border-radius: .6rem; }
.workspace-settings__identity { display: flex; flex-direction: column; flex: 1; min-width: 0; }
.workspace-settings__identity span { color: #64748b; font-size: .85rem; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.workspace-settings__identity small { color: #64748b; }
.workspace-settings__status { font-size: .75rem; border-radius: 1rem; padding: .2rem .6rem; background: #f0fdf4; color: #166534; }
.workspace-settings__status.is-disabled { color: #64748b; background: #f1f5f9; }
.workspace-settings__form h2, .workspace-settings__delete h2 { font-size: 1.3rem; margin: 1rem 0; }
.workspace-settings__form h3 { font-size: 1rem; font-weight: 600; }
.workspace-settings__preview { justify-content: flex-start; margin-bottom: 1.25rem; }
.workspace-settings__grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 1rem; }
.workspace-settings__check { display: flex; align-items: center; gap: .6rem; }
.workspace-settings__check input { margin: 0; }
.workspace-settings__form small, .workspace-settings__notice { color: #64748b; font-size: .85rem; }
.workspace-settings__notice { padding: .8rem; border-radius: .5rem; background: #f8fafc; margin-block: 1rem; }
.workspace-settings__error { color: #b91c1c; }
.workspace-settings__actions { display: flex; justify-content: flex-end; gap: .75rem; margin-top: 1.25rem; }
.workspace-settings__delete { padding: 1.75rem; }
.workspace-settings__link { display: block; border: 0; background: none; padding: .4rem 0; color: #2563eb; cursor: pointer; font-size: .8rem; }
.dark .workspace-settings__list, .dark .workspace-settings__row { border-color: #334155; }
.dark .workspace-settings__preview, .dark .workspace-settings__notice, .dark .workspace-settings__icon { background: #1e293b; color: #cbd5e1; }
@media (max-width: 640px) { .workspace-settings__grid { grid-template-columns: 1fr; } .workspace-settings__row { flex-wrap: wrap; } .workspace-settings__status { display: none; } }
</style>
