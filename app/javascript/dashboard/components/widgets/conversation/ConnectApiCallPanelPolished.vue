<script>
import ConnectApiCallPanelBase from './ConnectApiCallPanel.vue';

const INCOMING_RING_INTERVAL = 3000;
const OUTGOING_RING_INTERVAL = 4200;

export default {
  name: 'ConnectApiCallPanelPolished',
  extends: ConnectApiCallPanelBase,
  data() {
    return {
      ringAudioContext: null,
      ringTimer: null,
      ringMode: '',
      ringSignature: '',
      callAudioUnlockHandler: null,
    };
  },
  computed: {
    incomingCallRingEnabled() {
      const value = this.providerConfig.incoming_call_ring_enabled;
      if (value === undefined || value === null || value === '') return true;

      return (
        value === true ||
        value === 1 ||
        String(value).toLowerCase() === 'true' ||
        String(value) === '1'
      );
    },
  },
  watch: {
    primaryCall: {
      deep: true,
      handler() {
        this.syncCallSounds();
      },
    },
    incomingCallRingEnabled() {
      this.syncCallSounds();
    },
  },
  mounted() {
    this.registerCallAudioUnlock();
    this.syncCallSounds();
  },
  beforeDestroy() {
    this.stopCallSound();
    this.unregisterCallAudioUnlock();
    if (this.ringAudioContext) {
      this.ringAudioContext.close().catch(() => {});
      this.ringAudioContext = null;
    }
  },
  methods: {
    resetConversationState() {
      this.stopCallSound();
      return ConnectApiCallPanelBase.methods.resetConversationState.call(this);
    },
    async loadCalls(silent = false) {
      await ConnectApiCallPanelBase.methods.loadCalls.call(this, silent);
      this.syncCallSounds();
    },
    async makeCall() {
      this.startCallSound('outgoing', 'outgoing:pending');
      try {
        await ConnectApiCallPanelBase.methods.makeCall.call(this);
      } finally {
        this.syncCallSounds();
      }
    },
    async action(call, action) {
      if (['accept', 'reject', 'end_call'].includes(action)) {
        this.stopCallSound();
      }
      try {
        await ConnectApiCallPanelBase.methods.action.call(this, call, action);
      } finally {
        this.syncCallSounds();
      }
    },
    desiredCallSound() {
      if (
        this.primaryCall &&
        this.canAccept(this.primaryCall) &&
        this.incomingCallRingEnabled
      ) {
        return {
          mode: 'incoming',
          signature: `incoming:${this.callId(this.primaryCall)}`,
        };
      }

      if (
        this.primaryCall &&
        this.primaryCall.direction === 'outgoing' &&
        this.isActive(this.primaryCall) &&
        !this.isConnected(this.primaryCall)
      ) {
        return {
          mode: 'outgoing',
          signature: `outgoing:${this.callId(this.primaryCall)}`,
        };
      }

      return null;
    },
    syncCallSounds() {
      const desired = this.desiredCallSound();
      if (!desired) {
        this.stopCallSound();
        return;
      }

      if (
        this.ringMode === desired.mode &&
        this.ringSignature === desired.signature
      ) {
        return;
      }

      this.startCallSound(desired.mode, desired.signature);
    },
    startCallSound(mode, signature) {
      if (mode === 'incoming' && !this.incomingCallRingEnabled) return;
      if (this.ringMode === mode && this.ringSignature === signature) return;

      this.stopCallSound();
      this.ringMode = mode;
      this.ringSignature = signature;
      this.ensureRingAudioContext();
      this.playCurrentRingPattern();

      const interval =
        mode === 'incoming' ? INCOMING_RING_INTERVAL : OUTGOING_RING_INTERVAL;
      this.ringTimer = window.setInterval(() => {
        this.playCurrentRingPattern();
      }, interval);
    },
    stopCallSound() {
      if (this.ringTimer) {
        window.clearInterval(this.ringTimer);
        this.ringTimer = null;
      }
      this.ringMode = '';
      this.ringSignature = '';
    },
    playCurrentRingPattern() {
      if (this.ringMode === 'incoming') {
        this.playIncomingRingPattern();
      } else if (this.ringMode === 'outgoing') {
        this.playOutgoingRingPattern();
      }
    },
    playIncomingRingPattern() {
      [0, 0.82].forEach(delay => {
        this.playTone({
          frequency: 660,
          duration: 0.62,
          volume: 0.045,
          delay,
        });
        this.playTone({
          frequency: 880,
          duration: 0.62,
          volume: 0.03,
          delay,
        });
      });
    },
    playOutgoingRingPattern() {
      this.playTone({
        frequency: 425,
        duration: 1.05,
        volume: 0.028,
        delay: 0,
      });
    },
    playTone({ frequency, duration, volume, delay = 0 }) {
      const context = this.ensureRingAudioContext();
      if (!context || context.state !== 'running') return;

      const startAt = context.currentTime + delay;
      const endAt = startAt + duration;
      const oscillator = context.createOscillator();
      const gain = context.createGain();

      oscillator.type = 'sine';
      oscillator.frequency.setValueAtTime(frequency, startAt);
      gain.gain.setValueAtTime(0.0001, startAt);
      gain.gain.linearRampToValueAtTime(volume, startAt + 0.03);
      gain.gain.setValueAtTime(volume, Math.max(startAt + 0.03, endAt - 0.08));
      gain.gain.exponentialRampToValueAtTime(0.0001, endAt);

      oscillator.connect(gain);
      gain.connect(context.destination);
      oscillator.start(startAt);
      oscillator.stop(endAt + 0.03);
    },
    ensureRingAudioContext() {
      const AudioContextClass =
        window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return null;

      if (!this.ringAudioContext) {
        this.ringAudioContext = new AudioContextClass();
      }

      if (this.ringAudioContext.state === 'suspended') {
        this.ringAudioContext.resume().catch(() => {});
      }

      return this.ringAudioContext;
    },
    registerCallAudioUnlock() {
      if (this.callAudioUnlockHandler) return;

      this.callAudioUnlockHandler = () => {
        const context = this.ensureRingAudioContext();
        if (context && context.state === 'suspended') {
          context.resume().catch(() => {});
        }
        this.unregisterCallAudioUnlock();
        if (this.ringMode) {
          window.setTimeout(() => this.playCurrentRingPattern(), 20);
        }
      };

      window.addEventListener('pointerdown', this.callAudioUnlockHandler, {
        passive: true,
      });
      window.addEventListener('keydown', this.callAudioUnlockHandler);
      window.addEventListener('touchstart', this.callAudioUnlockHandler, {
        passive: true,
      });
    },
    unregisterCallAudioUnlock() {
      if (!this.callAudioUnlockHandler) return;

      window.removeEventListener('pointerdown', this.callAudioUnlockHandler);
      window.removeEventListener('keydown', this.callAudioUnlockHandler);
      window.removeEventListener('touchstart', this.callAudioUnlockHandler);
      this.callAudioUnlockHandler = null;
    },
  },
};
</script>

<template>
  <div v-if="visible" class="relative flex min-w-0 items-center gap-2">
    <div
      v-if="minimized && primaryCall"
      class="flex min-w-0 items-center gap-2 rounded-xl border border-slate-200 bg-white px-2 py-1.5 shadow-sm dark:border-slate-700 dark:bg-slate-900"
    >
      <button
        type="button"
        class="flex min-w-0 items-center gap-2 rounded-lg px-1 py-0.5 text-left hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-hub-500 dark:hover:bg-slate-800"
        title="Reexibir chamada"
        @click="restore"
      >
        <div class="relative shrink-0">
          <hub-thumbnail
            :src="contactThumbnail"
            :username="contactName"
            size="34px"
          />
          <span
            class="absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full ring-2 ring-white dark:ring-slate-900"
            :class="stateDotClass"
          />
        </div>
        <span class="min-w-0">
          <span class="block max-w-[150px] truncate text-xs font-semibold text-slate-900 dark:text-slate-100">
            {{ contactName }}
          </span>
          <span class="block max-w-[170px] truncate text-[11px] text-slate-500 dark:text-slate-400">
            {{ currentStateLabel }}
            <template v-if="currentDuration"> · {{ currentDuration }}</template>
          </span>
        </span>
      </button>

      <button
        v-if="canAccept(primaryCall)"
        type="button"
        class="rounded-lg bg-blue-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="busy"
        @click="compactAccept"
      >
        Atender
      </button>

      <hub-button
        size="small"
        variant="clear"
        color-scheme="secondary"
        :disabled="busy"
        @click="restore"
      >
        Exibir
      </hub-button>

      <button
        type="button"
        class="rounded-lg bg-red-600 px-2.5 py-1.5 text-xs font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
        :disabled="busy"
        @click="compactEnd"
      >
        {{ compactActionLabel }}
      </button>
    </div>

    <div v-if="!minimized" class="relative shrink-0">
      <hub-button
        v-tooltip="hasIncomingCall ? 'Chamada recebida' : 'Chamada WhatsApp'"
        variant="clear"
        color-scheme="secondary"
        icon="call"
        @click="toggle"
      />
      <span
        v-if="hasIncomingCall"
        class="pointer-events-none absolute right-1 top-1 h-2.5 w-2.5 rounded-full bg-amber-500 ring-2 ring-white dark:ring-slate-900"
      />
    </div>

    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-[1px]"
      @click.self="close"
    >
      <div
        class="w-full max-w-[430px] overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl dark:border-slate-700 dark:bg-slate-900"
      >
        <div class="flex items-center justify-between gap-3 border-b border-slate-100 px-4 py-3.5 dark:border-slate-800">
          <div class="flex min-w-0 items-center gap-3">
            <div class="relative shrink-0">
              <hub-thumbnail
                :src="contactThumbnail"
                :username="contactName"
                size="44px"
              />
              <span
                class="absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full ring-2 ring-white dark:ring-slate-900"
                :class="stateDotClass"
              />
            </div>
            <div class="min-w-0">
              <h3 class="m-0 truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
                {{ contactName }}
              </h3>
              <p class="m-0 mt-0.5 truncate text-xs text-slate-500 dark:text-slate-400">
                {{ contactPhone || 'Número indisponível' }}
              </p>
            </div>
          </div>

          <button
            v-if="hasActiveCall"
            type="button"
            class="flex h-8 w-8 items-center justify-center rounded-lg text-lg font-semibold text-slate-500 hover:bg-slate-100 hover:text-slate-800 focus:outline-none focus:ring-2 focus:ring-hub-500 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-100"
            title="Minimizar chamada"
            aria-label="Minimizar chamada"
            @click="minimize"
          >
            —
          </button>
          <button
            v-else
            type="button"
            class="flex h-8 w-8 items-center justify-center rounded-lg text-xl text-slate-400 hover:bg-slate-100 hover:text-slate-700 focus:outline-none focus:ring-2 focus:ring-hub-500 dark:hover:bg-slate-800 dark:hover:text-slate-200"
            title="Fechar"
            aria-label="Fechar"
            @click="close"
          >
            ×
          </button>
        </div>

        <div class="px-4 py-4">
          <div
            v-if="error"
            class="mb-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300"
          >
            {{ error }}
          </div>
          <div
            v-if="mediaError"
            class="mb-3 rounded-xl bg-amber-50 px-3 py-2 text-sm text-amber-700 dark:bg-amber-950/30 dark:text-amber-300"
          >
            {{ mediaError }}
          </div>
          <div
            v-if="feedback"
            class="mb-3 rounded-xl bg-emerald-50 px-3 py-2 text-sm text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300"
          >
            {{ feedback }}
          </div>

          <div v-if="loading" class="py-8 text-center text-sm text-slate-500">
            Carregando chamada…
          </div>

          <template v-else-if="primaryCall">
            <div class="rounded-2xl bg-slate-50 px-4 py-4 dark:bg-slate-800/60">
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <span
                    class="inline-flex rounded-full px-2.5 py-1 text-[11px] font-semibold"
                    :class="stateBadgeClass"
                  >
                    {{ currentDirectionLabel }} · {{ currentStateLabel }}
                  </span>
                  <div
                    v-if="currentDuration"
                    class="mt-2 font-mono text-2xl font-semibold tabular-nums text-slate-900 dark:text-slate-100"
                  >
                    {{ currentDuration }}
                  </div>
                  <div
                    v-else
                    class="mt-2 text-sm font-medium text-slate-800 dark:text-slate-100"
                  >
                    {{ currentStateLabel }}
                  </div>
                </div>

                <div class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-white text-xl shadow-sm ring-1 ring-slate-200 dark:bg-slate-900 dark:ring-slate-700">
                  ☎
                </div>
              </div>

              <div class="mt-4 flex flex-wrap items-center gap-2">
                <button
                  v-if="canAccept(primaryCall)"
                  type="button"
                  class="flex-1 rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-blue-700 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="busy"
                  @click="action(primaryCall, 'accept')"
                >
                  Atender
                </button>

                <button
                  v-if="canReject(primaryCall)"
                  type="button"
                  class="flex-1 rounded-xl bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="busy"
                  @click="action(primaryCall, 'reject')"
                >
                  Recusar
                </button>

                <hub-button
                  v-if="mediaCallId === callId(primaryCall)"
                  class="flex-1 justify-center"
                  variant="clear"
                  color-scheme="secondary"
                  :disabled="busy"
                  @click="action(primaryCall, 'mute')"
                >
                  {{ primaryCall.muted ? 'Ativar microfone' : 'Silenciar' }}
                </hub-button>

                <button
                  v-if="!canReject(primaryCall)"
                  type="button"
                  class="flex-1 rounded-xl bg-red-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
                  :disabled="busy"
                  @click="action(primaryCall, 'end_call')"
                >
                  Encerrar
                </button>
              </div>
            </div>

            <div class="mt-3 flex items-center justify-between gap-3 rounded-xl border border-slate-200 px-3 py-2.5 dark:border-slate-700">
              <div class="flex min-w-0 items-center gap-2">
                <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-slate-100 text-sm dark:bg-slate-800">
                  ♪
                </span>
                <div class="min-w-0">
                  <div class="text-xs font-semibold text-slate-800 dark:text-slate-100">
                    Áudio da chamada
                  </div>
                  <div class="truncate text-[11px]" :class="mediaStateClass">
                    {{ mediaStateLabel }}
                  </div>
                </div>
              </div>
              <button
                type="button"
                class="rounded-lg px-2 py-1 text-xs font-medium text-slate-500 hover:bg-slate-100 hover:text-slate-800 disabled:opacity-50 dark:hover:bg-slate-800 dark:hover:text-slate-200"
                :disabled="busy"
                @click="loadCalls()"
              >
                Atualizar
              </button>
            </div>
          </template>

          <template v-else>
            <div class="rounded-2xl border border-slate-200 bg-slate-50/50 px-4 py-4 dark:border-slate-700 dark:bg-slate-800/30">
              <div class="flex items-center gap-3">
                <div class="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-hub-75 text-lg text-hub-700 dark:bg-hub-800 dark:text-hub-100">
                  ☎
                </div>
                <div class="min-w-0 flex-1">
                  <div class="text-sm font-semibold text-slate-900 dark:text-slate-100">
                    Pronto para ligar
                  </div>
                  <div class="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                    Inicie uma chamada de voz.
                  </div>
                </div>
              </div>

              <hub-button
                class="mt-4 w-full justify-center"
                icon="call"
                :disabled="busy || loading"
                @click="makeCall"
              >
                Ligar para este contato
              </hub-button>
            </div>
          </template>
        </div>
      </div>
    </div>
  </div>
</template>
