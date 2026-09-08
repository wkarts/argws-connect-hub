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
      <div><strong>Protocolo:</strong> {{ providerLabel }}</div>
      <div><strong>Chamadas:</strong> {{ callsAvailable ? 'Voz habilitada' : 'Não disponível neste protocolo' }}</div>
      <div v-if="callsAvailable"><strong>Limite da instância:</strong> {{ config.voip_max_concurrent_calls || 'limite global' }}</div>
    </div>
    <div v-if="callsAvailable" class="mb-5 rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-800 dark:border-green-900 dark:bg-green-950/20 dark:text-green-300">
      O botão de chamada aparece no cabeçalho das conversas desta caixa. O áudio usa ticket temporário; token da Connect|API não é enviado ao navegador.
    </div>
    <div v-else class="mb-5 rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-300">
      Para habilitar chamadas, a migração desta instância para ZAPO deve ser feita explicitamente no HUB Admin. O HUB não migra sessões existentes de forma automática.
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
      <button type="button" class="button clear alert" @click="disconnect">Desconectar</button>
    </div>
  </div>
</template>

<script>
import { useAlert } from 'dashboard/composables';
export default {
  props: { inbox: { type: Object, required: true } },
  computed: {
    config() { return this.inbox.provider_config || {}; },
    callsAvailable() {
      return this.config.calls_supported || this.config.connect_api_provider === 'WHATSAPP-ZAPO';
    },
    providerLabel() {
      if (this.config.connect_api_provider === 'WHATSAPP-ZAPO') return 'ZAPO';
      if (this.config.connect_api_provider === 'WHATSAPP-BAILEYS') return 'Baileys';
      return this.config.connect_api_provider || 'Baileys';
    },
  },
  methods: {
    async update(extra) {
      try {
        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id, formData: false,
          channel: { provider_config: { ...this.config, ...extra } },
        });
        await this.$store.dispatch('inboxes/get');
      } catch (error) {
        useAlert(error?.response?.data?.message || 'Falha ao comunicar com a Connect|API.');
      }
    },
    connect(authMode) { return this.update({ auth_mode: authMode, connect: true, disconnect: false }); },
    disconnect() { return this.update({ disconnect: true, connect: false }); },
    refresh() { return this.update({ connect: false, disconnect: false }); },
  },
};
</script>
