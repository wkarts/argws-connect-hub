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
    accentClasses() {
      if (['rejected', 'missed', 'unanswered', 'failed'].includes(this.status)) {
        return 'border-l-red-500';
      }
      if (this.status === 'ringing') return 'border-l-amber-500';
      if (this.status === 'answered') return 'border-l-emerald-500';
      return 'border-l-slate-400';
    },
    statusClasses() {
      if (['rejected', 'missed', 'unanswered', 'failed'].includes(this.status)) {
        return 'bg-red-50 text-red-700 dark:bg-red-950/30 dark:text-red-300';
      }
      if (this.status === 'ringing') {
        return 'bg-amber-50 text-amber-700 dark:bg-amber-950/30 dark:text-amber-300';
      }
      if (this.status === 'answered') {
        return 'bg-emerald-50 text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300';
      }
      return 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300';
    },
    peerName() {
      return this.call.peer_name || 'Contato';
    },
    peerThumbnail() {
      return this.call.peer_thumbnail || '';
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
        return `+55 (${digits.slice(2, 4)}) ${digits.slice(4, 9)}-${digits.slice(9)}`;
      }
      if (digits.startsWith('55') && digits.length === 12) {
        return `+55 (${digits.slice(2, 4)}) ${digits.slice(4, 8)}-${digits.slice(8)}`;
      }
      return `+${digits}`;
    },
  },
};
</script>

<template>
  <div
    class="call-timeline-card mx-auto my-2 w-full max-w-[430px] overflow-hidden rounded-xl border border-slate-200 border-l-4 bg-white shadow-sm dark:border-slate-700 dark:bg-slate-900"
    :class="accentClasses"
  >
    <div class="flex items-center gap-3 px-3.5 py-3">
      <div class="relative shrink-0">
        <hub-thumbnail
          :src="peerThumbnail"
          :username="peerName"
          size="42px"
        />
        <span
          class="absolute -bottom-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-slate-900 text-[10px] text-white ring-2 ring-white dark:bg-slate-100 dark:text-slate-900 dark:ring-slate-900"
          aria-hidden="true"
        >
          ☎
        </span>
      </div>

      <div class="min-w-0 flex-1">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <div class="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">
              {{ peerName }}
            </div>
            <div class="mt-0.5 truncate text-xs text-slate-500 dark:text-slate-400">
              {{ title }} · {{ directionLabel }}
            </div>
          </div>

          <span
            class="shrink-0 rounded-full px-2 py-1 text-[11px] font-semibold"
            :class="statusClasses"
          >
            {{ statusLabel }}
          </span>
        </div>

        <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-slate-500 dark:text-slate-400">
          <span v-if="peerPhone">{{ peerPhone }}</span>
          <span v-if="timestampLabel">{{ timestampLabel }}</span>
          <span
            v-if="durationLabel"
            class="font-mono font-semibold tabular-nums text-slate-700 dark:text-slate-200"
          >
            {{ durationLabel }}
          </span>
          <span>{{ isVideo ? 'Vídeo' : 'Voz' }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
