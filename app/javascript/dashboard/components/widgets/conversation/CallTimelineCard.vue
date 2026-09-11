<script>
export default {
  props: {
    call: {
      type: Object,
      required: true,
    },
    messageCreatedAt: {
      type: [String, Number],
      default: null,
    },
  },
  computed: {
    status() {
      return String(this.call.status || 'unknown').toLowerCase();
    },
    isVideo() {
      const value = this.call.is_video;
      return (
        value === true ||
        value === 1 ||
        String(value).toLowerCase() === 'true' ||
        String(value) === '1'
      );
    },
    title() {
      return this.isVideo ? 'Chamada de vídeo' : 'Chamada de voz';
    },
    directionLabel() {
      if (this.call.direction === 'incoming') return 'Recebida';
      if (this.call.direction === 'outgoing') return 'Efetuada';
      return 'Chamada';
    },
    statusLabel() {
      const labels = {
        ringing: this.call.direction === 'incoming' ? 'Tocando' : 'Chamando',
        answered: 'Atendida',
        rejected: 'Recusada',
        missed: 'Perdida',
        unanswered: 'Não atendida',
        ended: 'Encerrada',
        failed: 'Falhou',
        answered_elsewhere: 'Atendida em outro dispositivo',
        unknown: 'Atualizando',
      };
      return labels[this.status] || 'Atualizando';
    },
    statusClasses() {
      if (
        ['rejected', 'missed', 'unanswered', 'failed'].includes(this.status)
      ) {
        return 'border-red-200 bg-red-50 text-red-700 dark:border-red-900/70 dark:bg-red-950/30 dark:text-red-300';
      }
      if (['ringing', 'answered'].includes(this.status)) {
        return 'border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900/70 dark:bg-emerald-950/30 dark:text-emerald-300';
      }
      return 'border-slate-200 bg-slate-50 text-slate-600 dark:border-slate-700 dark:bg-slate-800/60 dark:text-slate-300';
    },
    peerName() {
      return this.call.peer_name || '';
    },
    peerPhone() {
      return this.formatPhone(this.call.peer_phone);
    },
    durationLabel() {
      const value = Number(this.call.duration_seconds);
      if (!Number.isFinite(value) || value < 0) return '';

      const totalSeconds = Math.floor(value);
      const hours = Math.floor(totalSeconds / 3600);
      const minutes = Math.floor((totalSeconds % 3600) / 60);
      const seconds = totalSeconds % 60;
      const minuteText = String(minutes).padStart(2, '0');
      const secondText = String(seconds).padStart(2, '0');

      return hours > 0
        ? `${hours}:${minuteText}:${secondText}`
        : `${minuteText}:${secondText}`;
    },
    timestampLabel() {
      const value =
        this.call.started_at ||
        this.call.answered_at ||
        this.call.created_at ||
        this.call.received_at ||
        this.messageCreatedAt;
      const date = this.toDate(value);
      if (!date) return '';

      return new Intl.DateTimeFormat('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      }).format(date);
    },
  },
  methods: {
    toDate(value) {
      if (value === undefined || value === null || value === '') return null;

      const numeric = Number(value);
      if (Number.isFinite(numeric)) {
        const milliseconds = numeric < 100000000000 ? numeric * 1000 : numeric;
        const parsed = new Date(milliseconds);
        return Number.isNaN(parsed.getTime()) ? null : parsed;
      }

      const parsed = new Date(String(value));
      return Number.isNaN(parsed.getTime()) ? null : parsed;
    },
    formatPhone(value) {
      const digits = String(value || '').replace(/\D/g, '');
      if (!digits) return '';

      if (digits.startsWith('55') && digits.length === 13) {
        return `+55 (${digits.slice(2, 4)}) ${digits.slice(
          4,
          9
        )}-${digits.slice(9)}`;
      }
      if (digits.startsWith('55') && digits.length === 12) {
        return `+55 (${digits.slice(2, 4)}) ${digits.slice(
          4,
          8
        )}-${digits.slice(8)}`;
      }
      return `+${digits}`;
    },
  },
};
</script>

<template>
  <div
    class="mx-auto my-1 w-full max-w-[380px] overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm dark:border-slate-700 dark:bg-slate-900"
  >
    <div class="flex items-start gap-3 p-4">
      <div
        class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-lg text-white shadow-sm"
        aria-hidden="true"
      >
        ☎
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="min-w-0">
            <div class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
              {{ title }}
            </div>
            <div class="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
              {{ directionLabel }}
              <template v-if="timestampLabel"> · {{ timestampLabel }}</template>
            </div>
          </div>

          <span
            class="rounded-full border px-2 py-1 text-[11px] font-semibold"
            :class="statusClasses"
          >
            {{ statusLabel }}
          </span>
        </div>

        <div
          v-if="peerName || peerPhone"
          class="mt-3 rounded-xl bg-slate-50 px-3 py-2 dark:bg-slate-800/70"
        >
          <div
            v-if="peerName"
            class="truncate text-xs font-semibold text-slate-800 dark:text-slate-100"
          >
            {{ peerName }}
          </div>
          <div
            v-if="peerPhone"
            class="truncate text-[11px] text-slate-500 dark:text-slate-400"
          >
            {{ peerPhone }}
          </div>
        </div>

        <div class="mt-3 flex flex-wrap items-center gap-2 text-[11px] text-slate-500 dark:text-slate-400">
          <span
            v-if="isVideo"
            class="rounded-md bg-slate-100 px-2 py-1 font-medium text-slate-700 dark:bg-slate-800 dark:text-slate-200"
          >
            Vídeo
          </span>
          <span
            v-else
            class="rounded-md bg-slate-100 px-2 py-1 font-medium text-slate-700 dark:bg-slate-800 dark:text-slate-200"
          >
            Voz
          </span>
          <span
            v-if="durationLabel"
            class="rounded-md bg-slate-100 px-2 py-1 font-mono font-semibold tabular-nums text-slate-700 dark:bg-slate-800 dark:text-slate-200"
          >
            {{ durationLabel }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
