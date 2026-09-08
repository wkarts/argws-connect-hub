<template>
  <div class="my-4 mx-8 text-base max-w-3xl">
    <div class="mb-4">
      <h3 class="text-lg font-medium">Connect|API</h3>
      <p class="text-sm text-slate-500">Provider WhatsApp do HUB. A conexão pode usar QR Code ou código de pareamento; o tráfego de mensagens usa a camada Meta-compatible da Connect|API.</p>
    </div>
    <div class="grid grid-cols-2 gap-3 mb-5">
      <div><strong>Instância:</strong> {{ config.instance_name || '-' }}</div>
      <div><strong>Status:</strong> {{ config.connection_status || 'desconhecido' }}</div>
      <div><strong>Número:</strong> {{ inbox.phone_number }}</div>
      <div><strong>Meta-compatible:</strong> {{ config.meta_compatible ? 'Ativo' : 'Pendente' }}</div>
    </div>
    <div v-if="config.qrcode_base64" class="mb-5">
      <img :src="config.qrcode_base64" alt="QR Code WhatsApp" class="w-72 h-72" />
    </div>
    <div v-if="config.pairing_code" class="mb-5 p-4 rounded bg-slate-50 dark:bg-slate-800">
      <div class="text-sm text-slate-500">Código de pareamento</div>
      <div class="text-3xl font-mono tracking-widest">{{ config.pairing_code }}</div>
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
  computed: { config() { return this.inbox.provider_config || {}; } },
  methods: {
    async update(extra) {
      try {
        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id, formData: false,
          channel: { provider_config: { ...this.config, ...extra } }
        });
        await this.$store.dispatch('inboxes/get');
      } catch (error) {
        useAlert(error?.response?.data?.message || 'Falha ao comunicar com a Connect|API.');
      }
    },
    connect(authMode) { return this.update({ auth_mode: authMode, connect: true, disconnect: false }); },
    disconnect() { return this.update({ disconnect: true, connect: false }); },
    refresh() { return this.update({ connect: false, disconnect: false }); }
  }
};
</script>
