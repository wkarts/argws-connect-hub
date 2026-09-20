<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import EmailTranscriptModal from './EmailTranscriptModal.vue';
import ResolveAction from '../../buttons/ResolveAction.vue';
import {
  CMD_MUTE_CONVERSATION,
  CMD_SEND_TRANSCRIPT,
  CMD_UNMUTE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

const MUTE_OPTIONS = [
  { label: '30 minutos', value: 1800 },
  { label: '1 hora', value: 3600 },
  { label: '2 horas', value: 7200 },
  { label: '6 horas', value: 21600 },
  { label: '8 horas', value: 28800 },
  { label: 'Até eu reativar', value: 0 },
];

export default {
  components: {
    EmailTranscriptModal,
    ResolveAction,
  },
  data() {
    return {
      showEmailActionsModal: false,
      showMuteModal: false,
      muteDuration: 28800,
      isMuting: false,
      muteOptions: MUTE_OPTIONS,
    };
  },
  computed: {
    ...mapGetters({ currentChat: 'getSelectedChat' }),
  },
  mounted() {
    this.$emitter.on(CMD_MUTE_CONVERSATION, this.openMuteModal);
    this.$emitter.on(CMD_UNMUTE_CONVERSATION, this.unmute);
    this.$emitter.on(CMD_SEND_TRANSCRIPT, this.toggleEmailActionsModal);
  },
  destroyed() {
    this.$emitter.off(CMD_MUTE_CONVERSATION, this.openMuteModal);
    this.$emitter.off(CMD_UNMUTE_CONVERSATION, this.unmute);
    this.$emitter.off(CMD_SEND_TRANSCRIPT, this.toggleEmailActionsModal);
  },
  methods: {
    openMuteModal() {
      this.showMuteModal = true;
    },
    closeMuteModal() {
      if (!this.isMuting) this.showMuteModal = false;
    },
    async mute() {
      if (this.isMuting) return;

      this.isMuting = true;
      try {
        await this.$store.dispatch('muteConversation', {
          conversationId: this.currentChat.id,
          durationSeconds: Number(this.muteDuration),
        });
        this.showMuteModal = false;
        const selected = this.muteOptions.find(
          option => option.value === Number(this.muteDuration)
        );
        useAlert(
          selected?.value
            ? `Conversa silenciada por ${selected.label}.`
            : 'Conversa silenciada até você reativar.'
        );
      } catch (error) {
        useAlert(
          error?.response?.data?.error ||
            'Não foi possível silenciar a conversa.'
        );
      } finally {
        this.isMuting = false;
      }
    },
    async unmute() {
      try {
        await this.$store.dispatch('unmuteConversation', this.currentChat.id);
        useAlert('Silenciamento removido.');
      } catch (error) {
        useAlert('Não foi possível reativar as notificações desta conversa.');
      }
    },
    toggleEmailActionsModal() {
      this.showEmailActionsModal = !this.showEmailActionsModal;
    },
  },
};
</script>

<template>
  <div class="relative flex items-center gap-2 actions--container">
    <hub-button
      v-if="!currentChat.muted"
      v-tooltip="'Silenciar conversa'"
      variant="clear"
      color-scheme="secondary"
      icon="speaker-mute"
      title="Silenciar conversa"
      @click="openMuteModal"
    />
    <hub-button
      v-else
      v-tooltip.left="'Remover silenciamento'"
      variant="clear"
      color-scheme="secondary"
      icon="speaker-1"
      title="Remover silenciamento"
      @click="unmute"
    />
    <hub-button
      v-tooltip="$t('CONTACT_PANEL.SEND_TRANSCRIPT')"
      variant="clear"
      color-scheme="secondary"
      icon="share"
      @click="toggleEmailActionsModal"
    />
    <ResolveAction
      :conversation-id="currentChat.id"
      :status="currentChat.status"
    />

    <div
      v-if="showMuteModal"
      class="mute-dialog-backdrop"
      role="presentation"
      @click.self="closeMuteModal"
    >
      <section
        class="mute-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="hub-mute-title"
      >
        <h3 id="hub-mute-title">Silenciar conversa</h3>
        <p>
          O contato continuará podendo enviar e receber mensagens. Apenas as
          notificações desta conversa serão silenciadas; o contato não será
          bloqueado.
        </p>
        <label for="mute-duration">Por quanto tempo?</label>
        <select id="mute-duration" v-model.number="muteDuration">
          <option
            v-for="option in muteOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
        <div class="mute-dialog__actions">
          <hub-button
            variant="clear"
            color-scheme="secondary"
            :disabled="isMuting"
            @click="closeMuteModal"
          >
            Cancelar
          </hub-button>
          <hub-button :is-loading="isMuting" :disabled="isMuting" @click="mute">
            Silenciar
          </hub-button>
        </div>
      </section>
    </div>

    <EmailTranscriptModal
      v-if="showEmailActionsModal"
      :show="showEmailActionsModal"
      :current-chat="currentChat"
      @cancel="toggleEmailActionsModal"
    />
  </div>
</template>

<style scoped lang="scss">
.more--button {
  @apply items-center flex ml-2 rtl:ml-0 rtl:mr-2;
}

.dropdown-pane {
  @apply -right-2 top-12;
}

.icon {
  @apply mr-1 rtl:mr-0 rtl:ml-1 min-w-[1rem];
}

.mute-dialog-backdrop {
  @apply fixed inset-0 z-[9999] flex items-center justify-center p-4 bg-slate-900/50;
}

.mute-dialog {
  @apply flex flex-col gap-4 p-6 w-[30rem] max-w-full rounded-xl shadow-xl bg-white dark:bg-slate-900;

  h3 {
    @apply m-0 text-lg font-semibold text-slate-900 dark:text-slate-100;
  }

  p {
    @apply m-0 text-sm leading-5 text-slate-600 dark:text-slate-300;
  }

  label {
    @apply text-sm font-medium text-slate-700 dark:text-slate-200;
  }

  select {
    @apply w-full rounded-lg border border-slate-300 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-900 dark:text-slate-100;
  }
}

.mute-dialog__actions {
  @apply flex justify-end gap-2 mt-2;
}
</style>
