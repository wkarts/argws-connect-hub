<script>
import InboxAPI from 'dashboard/api/inboxes';
import { useAlert } from 'dashboard/composables';

export default {
  props: { inbox: { type: Object, required: true } },
  data() {
    return {
      templates: [],
      lastSyncedAt: null,
      loading: false,
      savingKey: null,
      error: '',
      requestSequence: 0,
    };
  },
  computed: {
    lastSyncLabel() {
      return this.lastSyncedAt
        ? new Date(this.lastSyncedAt).toLocaleString('pt-BR')
        : 'Ainda não sincronizado';
    },
  },
  watch: {
    'inbox.id': {
      immediate: true,
      handler() { this.loadTemplates(); },
    },
  },
  methods: {
    key(template) {
      return JSON.stringify([template.name, template.language]);
    },
    applyCatalog(data) {
      this.templates = data.payload || [];
      this.lastSyncedAt = data.last_synced_at;
    },
    async loadTemplates() {
      const inboxId = this.inbox.id;
      const sequence = ++this.requestSequence;
      this.loading = true;
      this.error = '';
      this.templates = [];
      this.lastSyncedAt = null;
      try {
        const { data } = await InboxAPI.getOpeningTemplates(inboxId);
        if (sequence === this.requestSequence && inboxId === this.inbox.id) this.applyCatalog(data);
      } catch (error) {
        if (sequence === this.requestSequence) {
          this.error = error?.response?.data?.message || 'Não foi possível carregar os templates desta caixa.';
        }
      } finally {
        if (sequence === this.requestSequence) this.loading = false;
      }
    },
    async setEnabled(template, event) {
      const enabled = event.target.checked;
      // Keep the persisted state on screen until the server confirms the change.
      event.target.checked = template.hub_opening_enabled === true;
      if (this.savingKey || this.loading) return;
      const inboxId = this.inbox.id;
      const sequence = this.requestSequence;
      this.savingKey = this.key(template);
      try {
        const data = await this.$store.dispatch('inboxes/setOpeningTemplate', {
          inboxId,
          name: template.name,
          language: template.language,
          enabled,
        });
        if (inboxId === this.inbox.id && sequence === this.requestSequence) this.applyCatalog(data);
        useAlert('Preferência do template atualizada nesta caixa.');
      } catch (error) {
        useAlert(error?.response?.data?.message || 'Não foi possível alterar este template.');
      } finally {
        this.savingKey = null;
      }
    },
    remoteLabel(template) {
      if (!template.hub_remote_present) return 'Não disponível na Connect|API';
      if (!template.hub_remote_available) return template.status || 'Indisponível';
      return template.status || 'Disponível';
    },
  },
};
</script>

<template>
  <section class="my-6 rounded-xl border border-slate-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-900" aria-labelledby="opening-templates-title">
    <h4 id="opening-templates-title" class="mb-2 text-base font-semibold text-slate-900 dark:text-slate-100">Templates de abertura</h4>
    <p class="mb-2 text-sm text-slate-600 dark:text-slate-300">
      Templates reais importados da Connect|API para esta caixa. Na primeira descoberta, somente o nome exato <strong>hello</strong> é habilitado. Suas escolhas são preservadas nas próximas reconciliações.
    </p>
    <p class="mb-4 text-xs text-slate-500 dark:text-slate-400">Última sincronização: {{ lastSyncLabel }}</p>
    <p v-if="loading" class="text-sm text-slate-500" role="status">Carregando templates...</p>
    <p v-else-if="error" class="text-sm text-red-700 dark:text-red-300" role="alert">{{ error }}</p>
    <p v-else-if="!templates.length" class="mb-0 text-sm text-slate-600 dark:text-slate-300">
      Nenhum template foi disponibilizado para esta caixa. Use Reconciliar agora para consultar a Connect|API. O HUB não cria o template hello nem substitui templates por mensagens livres.
    </p>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-left text-sm">
        <thead class="text-slate-600 dark:text-slate-300">
          <tr>
            <th class="px-2 py-3" scope="col">Template</th>
            <th class="px-2 py-3" scope="col">Idioma</th>
            <th class="px-2 py-3" scope="col">Categoria / Status</th>
            <th class="px-2 py-3 text-right" scope="col">Liberado para abertura</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="template in templates" :key="key(template)" class="border-t border-slate-100 dark:border-slate-800">
            <td class="px-2 py-3 font-medium text-slate-900 dark:text-slate-100">{{ template.name }}</td>
            <td class="px-2 py-3">{{ template.language }}</td>
            <td class="px-2 py-3">
              <div>{{ template.category || 'Não informada' }}</div>
              <div class="mt-1 text-xs" :class="template.hub_remote_available ? 'text-emerald-700 dark:text-emerald-300' : 'text-amber-700 dark:text-amber-300'">{{ remoteLabel(template) }}</div>
            </td>
            <td class="px-2 py-3 text-right">
              <label class="relative inline-flex cursor-pointer items-center">
                <input
                  type="checkbox"
                  role="switch"
                  class="peer sr-only"
                  :checked="template.hub_opening_enabled === true"
                  :disabled="Boolean(savingKey) || loading"
                  :aria-label="`Liberar ${template.name} (${template.language}) para abertura`"
                  :aria-checked="template.hub_opening_enabled === true"
                  :aria-busy="savingKey === key(template)"
                  @change="setEnabled(template, $event)"
                />
                <span class="h-6 w-11 rounded-full bg-slate-300 transition peer-checked:bg-hub-500 peer-focus-visible:ring-2 peer-focus-visible:ring-hub-500 peer-focus-visible:ring-offset-2 peer-disabled:opacity-50 dark:bg-slate-600" />
                <span class="pointer-events-none absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform peer-checked:translate-x-5" />
              </label>
            </td>
          </tr>
        </tbody>
      </table>
      <p class="mb-0 mt-3 text-xs text-slate-500 dark:text-slate-400">
        Um template liberado só aparece em Nova conversa enquanto também estiver disponível e aprovado na Connect|API, quando houver status de aprovação.
      </p>
    </div>
  </section>
</template>
