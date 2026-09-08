<script>
import connectApiCalls from 'dashboard/api/connectApiCalls';
import { ConnectApiVoiceMediaSession } from 'dashboard/services/connectApiVoiceMedia';

const ENDED_STATES = ['ended', 'end', 'terminated', 'rejected', 'closed'];

export default {
  props: {
    conversationId: {
      type: [String, Number],
      required: true,
    },
    inbox: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      open: false,
      loading: false,
      busy: false,
      calls: [],
      capabilities: {},
      error: '',
      feedback: '',
      pollTimer: null,
      voiceSession: null,
      mediaCallId: '',
      mediaState: 'idle',
      mediaError: '',
    };
  },
  computed: {
    providerConfig() {
      return this.inbox.provider_config || {};
    },
    visible() {
      return (
        this.inbox.provider === 'connectapi' &&
        (this.providerConfig.calls_supported ||
          this.providerConfig.connect_api_provider === 'WHATSAPP-ZAPO')
      );
    },
    activeCalls() {
      return this.calls.filter(call => this.isActive(call));
    },
    hasIncomingCall() {
      return this.activeCalls.some(call => this.canAccept(call));
    },
    mediaStateLabel() {
      const labels = {
        idle: 'Áudio não conectado',
        requesting_microphone: 'Aguardando microfone',
        connecting: 'Conectando áudio',
        ready: 'Áudio conectado',
        closed: 'Áudio encerrado',
        error: 'Falha no áudio',
      };
      return labels[this.mediaState] || this.mediaState;
    },
  },
  watch: {
    conversationId() {
      this.closeMedia();
      if (this.visible) this.loadCalls(true);
    },
  },
  mounted() {
    if (this.visible) {
      this.loadCalls(true);
      this.startPolling();
    }
  },
  beforeDestroy() {
    this.stopPolling();
    this.closeMedia();
  },
  methods: {
    async toggle() {
      this.open = !this.open;
      if (this.open) await this.loadCalls();
    },
    close() {
      this.open = false;
    },
    startPolling() {
      this.stopPolling();
      this.pollTimer = window.setInterval(() => this.loadCalls(true), 3000);
    },
    stopPolling() {
      if (this.pollTimer) window.clearInterval(this.pollTimer);
      this.pollTimer = null;
    },
    isActive(call) {
      return !ENDED_STATES.includes(String(call.state || '').toLowerCase());
    },
    canAccept(call) {
      if (call.direction !== 'incoming' || !this.isActive(call)) return false;
      if (call.canAccept !== undefined && call.canAccept !== null) return Boolean(call.canAccept);
      const state = String(call.state || '').toLowerCase();
      return state.includes('ring') || state.includes('incoming') || state.includes('offer');
    },
    canReject(call) {
      if (call.direction !== 'incoming' || !this.isActive(call)) return false;
      if (call.canReject !== undefined && call.canReject !== null) return Boolean(call.canReject);
      return this.canAccept(call);
    },
    callId(call) {
      return String(call.callId || call.id || '');
    },
    async loadCalls(silent = false) {
      if (!silent) this.loading = true;
      if (!silent) this.error = '';
      try {
        const { data } = await connectApiCalls.status(this.conversationId);
        this.calls = Array.isArray(data.calls) ? data.calls : [];
        this.capabilities = data.capabilities || {};
        if (this.mediaCallId) {
          const current = this.calls.find(call => this.callId(call) === this.mediaCallId);
          if (!current || !this.isActive(current)) this.closeMedia();
        }
      } catch (error) {
        if (!silent) this.error = this.apiError(error);
      } finally {
        if (!silent) this.loading = false;
      }
    },
    async makeCall() {
      this.busy = true;
      this.error = '';
      this.feedback = '';
      try {
        const { data } = await connectApiCalls.offer(this.conversationId);
        const callId = String(data.callId || data.id || '');
        this.feedback = 'Chamada iniciada.';
        if (callId && this.capabilities.voice !== false) await this.attachMedia(callId);
        await this.loadCalls(true);
      } catch (error) {
        this.error = this.apiError(error);
      } finally {
        this.busy = false;
      }
    },
    async action(call, action) {
      const callId = this.callId(call);
      if (!callId) return;
      this.busy = true;
      this.error = '';
      this.feedback = '';
      try {
        const nextMuted = !Boolean(call.muted);
        const payload = action === 'mute'
          ? { call_id: callId, muted: nextMuted }
          : { call_id: callId };
        await connectApiCalls.action(this.conversationId, action, payload);
        if (action === 'accept') {
          await this.attachMedia(callId);
          this.feedback = 'Chamada atendida; áudio conectado.';
        } else if (action === 'reject') {
          if (this.mediaCallId === callId) this.closeMedia();
          this.feedback = 'Chamada recusada.';
        } else if (action === 'end_call') {
          if (this.mediaCallId === callId) this.closeMedia();
          this.feedback = 'Chamada encerrada.';
        } else if (action === 'mute') {
          if (this.mediaCallId === callId && this.voiceSession) {
            this.voiceSession.setMicMuted(nextMuted);
          }
          this.feedback = nextMuted ? 'Microfone silenciado.' : 'Microfone ativado.';
        }
        await this.loadCalls(true);
      } catch (error) {
        this.error = this.apiError(error);
      } finally {
        this.busy = false;
      }
    },
    async requestMediaTicket(callId) {
      let lastError = null;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          return await connectApiCalls.mediaTicket(this.conversationId, callId);
        } catch (error) {
          lastError = error;
          if (error?.response?.status !== 404 || attempt === 2) throw error;
          await new Promise(resolve => window.setTimeout(resolve, 250 * (attempt + 1)));
        }
      }
      throw lastError;
    },
    async attachMedia(callId) {
      this.closeMedia();
      this.mediaCallId = callId;
      this.mediaError = '';
      try {
        const { data } = await this.requestMediaTicket(callId);
        this.voiceSession = new ConnectApiVoiceMediaSession(
          { mediaUrl: data.media_url, ticket: data.ticket },
          {
            onState: state => { this.mediaState = state; },
            onError: message => { this.mediaError = message; },
          }
        );
        await this.voiceSession.start();
      } catch (error) {
        this.mediaError = this.apiError(error);
        this.mediaState = 'error';
        if (this.voiceSession) this.voiceSession.stop();
        this.voiceSession = null;
      }
    },
    closeMedia() {
      if (this.voiceSession) this.voiceSession.stop();
      this.voiceSession = null;
      this.mediaCallId = '';
      if (this.mediaState !== 'error') this.mediaState = 'idle';
    },
    directionLabel(call) {
      if (call.direction === 'incoming') return 'Recebida';
      if (call.direction === 'outgoing') return 'Efetuada';
      return 'Chamada';
    },
    stateLabel(call) {
      const state = String(call.state || '').toLowerCase();
      if (state.includes('ring')) return 'Chamando';
      if (state.includes('accept') || state.includes('active') || state.includes('connect')) return 'Em andamento';
      if (state.includes('reject')) return 'Recusada';
      if (state.includes('end') || state.includes('termin') || state.includes('close')) return 'Encerrada';
      return call.state || 'Em andamento';
    },
    peerLabel(call) {
      return call.name || call.contactName || call.number || call.callerPn || call.displayPeerJid || call.peerJid || 'WhatsApp';
    },
    apiError(error) {
      return (
        error?.response?.data?.error ||
        error?.response?.data?.message ||
        error?.message ||
        'Falha ao comunicar com a Connect|API.'
      );
    },
  },
};
</script>

<template>
  <div v-if="visible" class="relative">
    <div class="relative">
      <hub-button
        v-tooltip="hasIncomingCall ? 'Chamada WhatsApp recebida' : 'Chamada WhatsApp via Connect|API'"
        variant="clear"
        color-scheme="secondary"
        icon="call"
        @click="toggle"
      />
      <span
        v-if="hasIncomingCall"
        class="pointer-events-none absolute right-0 top-0 h-2.5 w-2.5 rounded-full bg-red-500 ring-2 ring-white dark:ring-slate-900"
      />
    </div>

    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      @click.self="close"
    >
      <div class="w-full max-w-xl rounded-xl bg-white p-5 shadow-xl dark:bg-slate-900">
        <div class="mb-4 flex items-start justify-between gap-3">
          <div>
            <h3 class="m-0 text-lg font-semibold text-slate-900 dark:text-slate-100">Chamada WhatsApp</h3>
            <p class="m-0 mt-1 text-xs text-slate-500">Connect|API · {{ capabilities.provider || providerConfig.connect_api_provider }}</p>
          </div>
          <hub-button variant="clear" color-scheme="secondary" icon="dismiss" @click="close" />
        </div>

        <div v-if="error" class="mb-3 rounded-md bg-red-50 p-3 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300">{{ error }}</div>
        <div v-if="mediaError" class="mb-3 rounded-md bg-yellow-50 p-3 text-sm text-yellow-700 dark:bg-yellow-950/30 dark:text-yellow-300">{{ mediaError }}</div>
        <div v-if="feedback" class="mb-3 rounded-md bg-green-50 p-3 text-sm text-green-700 dark:bg-green-950/30 dark:text-green-300">{{ feedback }}</div>

        <div class="mb-4 flex items-center justify-between rounded-lg border border-slate-200 p-3 dark:border-slate-700">
          <div>
            <div class="text-sm font-medium text-slate-800 dark:text-slate-100">Áudio do navegador</div>
            <div class="text-xs text-slate-500">{{ mediaStateLabel }}</div>
          </div>
          <span v-if="mediaCallId" class="text-xs font-mono text-slate-500">{{ mediaCallId }}</span>
        </div>

        <div v-if="loading" class="py-8 text-center text-sm text-slate-500">Carregando chamadas…</div>
        <div v-else-if="activeCalls.length" class="mb-4 space-y-2">
          <div
            v-for="call in activeCalls"
            :key="callId(call)"
            class="rounded-lg border border-slate-200 p-3 dark:border-slate-700"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <div>
                <div class="text-sm font-medium text-slate-900 dark:text-slate-100">{{ peerLabel(call) }}</div>
                <div class="text-xs text-slate-500">{{ directionLabel(call) }} · {{ stateLabel(call) }}</div>
              </div>
              <div class="flex flex-wrap gap-2">
                <hub-button
                  v-if="canAccept(call)"
                  size="small"
                  :disabled="busy"
                  @click="action(call, 'accept')"
                >Atender</hub-button>
                <hub-button
                  v-if="canReject(call)"
                  size="small"
                  variant="clear"
                  color-scheme="alert"
                  :disabled="busy"
                  @click="action(call, 'reject')"
                >Recusar</hub-button>
                <hub-button
                  v-if="mediaCallId === callId(call)"
                  size="small"
                  variant="clear"
                  :disabled="busy"
                  @click="action(call, 'mute')"
                >{{ call.muted ? 'Ativar mic' : 'Silenciar' }}</hub-button>
                <hub-button
                  size="small"
                  variant="clear"
                  color-scheme="alert"
                  :disabled="busy"
                  @click="action(call, 'end_call')"
                >Encerrar</hub-button>
              </div>
            </div>
          </div>
        </div>
        <div v-else class="mb-4 rounded-lg border border-dashed border-slate-200 p-5 text-center text-sm text-slate-500 dark:border-slate-700">
          Nenhuma chamada ativa nesta instância.
        </div>

        <div class="flex justify-end gap-2">
          <hub-button variant="clear" color-scheme="secondary" :disabled="busy" @click="loadCalls()">Atualizar</hub-button>
          <hub-button icon="call" :disabled="busy || loading" @click="makeCall">Ligar para este contato</hub-button>
        </div>
      </div>
    </div>
  </div>
</template>
