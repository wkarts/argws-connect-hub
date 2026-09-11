<template>
  <div class="my-4 mx-8 max-w-3xl text-base">
    <div class="mb-4">
      <h3 class="text-lg font-medium">Connect|API</h3>
      <p class="text-sm text-slate-500">
        Integração WhatsApp nativa do HUB. Mensagens usam a compatibilidade Meta; chamadas de voz ficam disponíveis nas instâncias ZAPO.
      </p>
    </div>
    <div class="mb-5 grid grid-cols-2 gap-3">
      <div><strong>Instância:</strong> {{ config.instance_name || '-' }}</div>
      <div><strong>Status:</strong> {{ config.connection_status || 'desconhecido' }}</div>
      <div><strong>Número:</strong> {{ inbox.phone_number }}</div>
      <div><strong>Meta-compatible:</strong> {{ config.meta_compatible ? 'Ativo' : 'Pendente' }}</div>
      <div><strong>Comunicação:</strong> {{ communicationLabel }}</div>
      <div><strong>Protocolo:</strong> {{ providerLabel }}</div>
      <div><strong>Chamadas:</strong> {{ callsAvailable ? 'Voz habilitada' : 'Não disponível neste protocolo' }}</div>
      <div v-if="callsAvailable"><strong>Limite da instância:</strong> {{ config.voip_max_concurrent_calls || 'limite global' }}</div>
    </div>
    <div
      v-if="config.connect_api_manual_deletion"
      class="mb-5 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-900 dark:bg-amber-950/20 dark:text-amber-300"
    >
      A instância foi excluída pelo administrador. Clique em <strong>Reconciliar agora</strong> para recriá-la e reconfigurar o webhook.
    </div>
    <div v-if="callsAvailable" class="mb-5 rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-800 dark:border-green-900 dark:bg-green-950/20 dark:text-green-300">
      O botão de chamada aparece no cabeçalho das conversas desta caixa. O áudio usa ticket temporário; token da Connect|API não é enviado ao navegador.
    </div>
    <div v-else class="mb-5 rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300">
      Para habilitar chamadas, a migração desta instância para ZAPO deve ser feita explicitamente no HUB Admin. O HUB não migra sessões existentes de forma automática.
    </div>

    <div
      v-if="callsAvailable"
      class="mb-5 flex items-center justify-between gap-4 rounded-lg border border-slate-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-900"
    >
      <div class="min-w-0">
        <div class="text-sm font-semibold text-slate-800 dark:text-slate-100">
          Toque de chamada recebida na conversa
        </div>
        <p class="mb-0 mt-1 text-xs leading-5 text-slate-500 dark:text-slate-400">
          Reproduz um toque enquanto a conversa estiver aberta e houver uma chamada recebida tocando. O padrão é ativado.
        </p>
      </div>
      <label class="relative inline-flex shrink-0 cursor-pointer items-center">
        <input
          type="checkbox"
          class="peer sr-only"
          :checked="incomingCallRingEnabled"
          :disabled="isSavingIncomingCallRing"
          aria-label="Ativar toque de chamada recebida na conversa"
          @change="setIncomingCallRing($event.target.checked)"
        />
        <span
          class="h-6 w-11 rounded-full bg-slate-300 transition peer-checked:bg-hub-500 peer-disabled:cursor-not-allowed peer-disabled:opacity-50 dark:bg-slate-600"
        />
        <span
          class="pointer-events-none absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform peer-checked:translate-x-5"
        />
      </label>
    </div>

    <div v-if="config.qrcode_base64" class="mb-5">
      <img :src="config.qrcode_base64" alt="QR Code WhatsApp" class="h-72 w-72" />
    </div>
    <div v-if="config.pairing_code" class="mb-5 rounded bg-slate-50 p-4 dark:bg-slate-800">
      <div class="text-sm text-slate-500">Código de pareamento</div>
      <div class="font-mono text-3xl tracking-widest">{{ config.pairing_code }}</div>
    </div>
    <div class="flex flex-wrap gap-2">
      <button type="button" class="button nice" @click="connect('qrcode')">Gerar QR Code</button>
      <button type="button" class="button nice" @click="connect('pairing_code')">Gerar código de pareamento</button>
      <button type="button" class="button nice" @click="refresh">Atualizar status</button>
      <button type="button" class="button nice" :disabled="isReconciling" @click="reconcile">
        {{ isReconciling ? 'Reconciliando...' : 'Reconciliar agora' }}
      </button>
      <button type="button" class="button clear alert" @click="disconnect">Desconectar</button>
    </div>
  </div>
</template>

<script>
import { useAlert } from 'dashboard/composables';
export default {
  props: { inbox: { type: Object, required: true } },
  data() {
    return {
      isReconciling: false,
      isSavingIncomingCallRing: false,
    };
  },
  computed: {
    config() { return this.inbox.provider_config || {}; },
    callsAvailable() {
      return this.config.calls_supported || this.config.connect_api_provider === 'WHATSAPP-ZAPO';
    },
    incomingCallRingEnabled() {
      const value = this.config.incoming_call_ring_enabled;
      if (value === undefined || value === null || value === '') return true;

      return (
        value === true ||
        value === 1 ||
        String(value).toLowerCase() === 'true' ||
        String(value) === '1'
      );
    },
    communicationLabel() {
      if (this.config.connect_api_manual_deletion) return 'Instância removida';
      if (this.config.communication_ready && this.config.meta_compatible_verified) return 'Sincronizada';
      return 'Requer reconciliação';
    },
    providerLabel() {
      if (this.config.connect_api_provider === 'WHATSAPP-ZAPO') return 'ZAPO';
      if (this.config.connect_api_provider === 'WHATSAPP-BAILEYS') return 'Baileys';
      return this.config.connect_api_provider || 'Baileys';
    },
  },
  methods: {
    async update(extra, successMessage = '') {
      try {
        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id, formData: false,
          channel: { provider_config: { ...this.config, ...extra } },
        });
        await this.$store.dispatch('inboxes/get');
        if (successMessage) useAlert(successMessage);
        return true;
      } catch (error) {
        useAlert(error?.response?.data?.message || 'Falha ao comunicar com a Connect|API.');
        return false;
      }
    },
    async setIncomingCallRing(enabled) {
      if (this.isSavingIncomingCallRing) return;
      this.isSavingIncomingCallRing = true;
      try {
        await this.update(
          { incoming_call_ring_enabled: Boolean(enabled) },
          enabled
            ? 'Toque de chamada recebida ativado nesta caixa.'
            : 'Toque de chamada recebida desativado nesta caixa.'
        );
      } finally {
        this.isSavingIncomingCallRing = false;
      }
    },
    connect(authMode) { return this.update({ auth_mode: authMode, connect: true, disconnect: false }); },
    disconnect() { return this.update({ disconnect: true, connect: false }); },
    refresh() { return this.update({ connect: false, disconnect: false }); },
    async reconcile() {
      if (this.isReconciling) return;
      this.isReconciling = true;
      try {
        await this.update(
          { force_reconcile: true, connect: false, disconnect: false },
          'Caixa reconciliada com a Connect|API.'
        );
      } finally {
        this.isReconciling = false;
      }
    },
  },
};
</script>
