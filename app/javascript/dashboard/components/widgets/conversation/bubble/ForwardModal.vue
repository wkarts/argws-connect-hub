<template>
  <hub-modal modal-type="right-aligned" show :on-close="onClose">
    <section class="forward-panel" aria-label="Encaminhar mensagem">
      <header class="forward-panel__header">
        <div>
          <h1>Encaminhar mensagem</h1>
          <p>
            Selecione um ou mais contatos. Ao escolher somente um destino, o HUB
            abrirá a conversa encaminhada assim que a mensagem for criada.
          </p>
        </div>
        <span v-if="selectedCount" class="forward-panel__counter">
          {{ selectedCount }} selecionado<span v-if="selectedCount > 1">s</span>
        </span>
      </header>

      <div class="forward-panel__search">
        <fluent-icon icon="search" size="18" />
        <input
          v-model="searchQuery"
          type="search"
          name="contact"
          autocomplete="off"
          placeholder="Buscar por nome ou telefone"
          aria-label="Buscar contato"
          @input="scheduleSearch"
          @keyup.enter="fetchContacts"
          @search="scheduleSearch"
        />
      </div>

      <div class="forward-panel__list" role="list">
        <button
          v-for="contact in contacts"
          :key="contact.id"
          type="button"
          class="forward-contact"
          :class="{ 'is-selected': isSelected(contact.id) }"
          role="listitem"
          @click="toggleContact(contact.id)"
        >
          <span class="forward-contact__check" aria-hidden="true">
            <fluent-icon
              :icon="isSelected(contact.id) ? 'checkmark-circle' : 'circle'"
              size="20"
            />
          </span>
          <Thumbnail
            :src="contact.thumbnail"
            :username="contact.name"
            size="42px"
          />
          <span class="forward-contact__identity">
            <strong>{{ contact.name || 'Contato sem nome' }}</strong>
            <small>{{ contact.phone_number || contact.email || 'Sem telefone' }}</small>
          </span>
          <span class="forward-contact__activity">
            <time-ago
              :last-activity-timestamp="contact.last_activity_at"
              :created-at-timestamp="contact.created_at"
            />
          </span>
        </button>

        <div v-if="!contacts.length && !isLoadingContacts" class="forward-panel__empty">
          <fluent-icon icon="people" size="28" />
          <strong>Nenhum contato encontrado</strong>
          <span>Revise a busca e tente novamente.</span>
        </div>
      </div>

      <footer class="forward-panel__footer">
        <span class="forward-panel__hint">
          <template v-if="selectedCount === 1">
            A conversa de destino será aberta após o encaminhamento.
          </template>
          <template v-else-if="selectedCount > 1">
            As mensagens serão encaminhadas em segundo plano.
          </template>
          <template v-else>
            Selecione pelo menos um destinatário.
          </template>
        </span>
        <div class="forward-panel__actions">
          <hub-button
            variant="clear"
            color-scheme="secondary"
            :disabled="isSubmitting"
            @click="onClose"
          >
            Cancelar
          </hub-button>
          <hub-button
            :disabled="!selectedCount || isSubmitting"
            :is-loading="isSubmitting"
            @click="onSubmit"
          >
            Encaminhar
          </hub-button>
        </div>
      </footer>
    </section>
  </hub-modal>
</template>

<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import TimeAgo from 'dashboard/components/ui/TimeAgo';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';
import { conversationUrl } from 'dashboard/helper/URLHelper';

const DEFAULT_PAGE = 1;
const SEARCH_DELAY = 250;

export default {
  components: {
    TimeAgo,
    Thumbnail,
  },
  props: {
    message: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      searchQuery: '',
      selectedContactIds: [],
      isSubmitting: false,
      searchTimer: null,
    };
  },
  computed: {
    ...mapGetters({
      contacts: 'contacts/getContacts',
      currentAccountId: 'getCurrentAccountId',
      contactsUIFlags: 'contacts/getUIFlags',
    }),
    selectedCount() {
      return this.selectedContactIds.length;
    },
    isLoadingContacts() {
      return !!this.contactsUIFlags?.isFetching;
    },
  },
  mounted() {
    this.fetchContacts();
  },
  beforeDestroy() {
    if (this.searchTimer) clearTimeout(this.searchTimer);
  },
  methods: {
    onClose() {
      if (!this.isSubmitting) this.$emit('close');
    },
    normalizedSearch() {
      return this.searchQuery.trim().replace(/^\+/, '');
    },
    fetchContacts() {
      const requestParams = {
        page: DEFAULT_PAGE,
        sortAttr: '-last_activity_at',
      };
      const value = this.normalizedSearch();

      if (!value) {
        return this.$store.dispatch('contacts/get', requestParams);
      }

      return this.$store.dispatch('contacts/search', {
        search: encodeURIComponent(value),
        ...requestParams,
      });
    },
    scheduleSearch() {
      if (this.searchTimer) clearTimeout(this.searchTimer);
      this.searchTimer = setTimeout(() => this.fetchContacts(), SEARCH_DELAY);
    },
    isSelected(contactId) {
      return this.selectedContactIds.includes(Number(contactId));
    },
    toggleContact(contactId) {
      const id = Number(contactId);
      this.selectedContactIds = this.isSelected(id)
        ? this.selectedContactIds.filter(item => item !== id)
        : [...this.selectedContactIds, id];
    },
    async onSubmit() {
      if (!this.selectedCount || this.isSubmitting) return;

      this.isSubmitting = true;
      try {
        const response = await this.$store.dispatch('forwardMessage', {
          conversationId: this.message.conversation_id,
          messageId: this.message.id,
          contacts: this.selectedContactIds,
        });

        const destination = response?.destination;
        if (this.selectedCount === 1 && destination?.conversation_id) {
          useAlert('Mensagem encaminhada com sucesso.');
          this.$emit('close');
          await this.$router.push(
            conversationUrl({
              accountId: this.currentAccountId,
              id: destination.conversation_id,
            })
          );
          return;
        }

        useAlert(
          `Mensagem encaminhada para ${response?.destination_count || this.selectedCount} destinatários.`
        );
        this.$emit('close');
      } catch (error) {
        const message =
          error?.response?.data?.error ||
          'Não foi possível encaminhar a mensagem. Tente novamente.';
        useAlert(message);
      } finally {
        this.isSubmitting = false;
      }
    },
  },
};
</script>

<style lang="scss" scoped>
::v-deep .modal--close {
  z-index: 3;
}

.forward-panel {
  @apply flex flex-col h-full min-w-[28rem] max-w-[36rem] bg-white dark:bg-slate-900 text-slate-800 dark:text-slate-100;
}

.forward-panel__header {
  @apply flex items-start justify-between gap-4 px-6 pt-6 pb-4 border-b border-slate-100 dark:border-slate-800;

  h1 {
    @apply m-0 text-xl font-semibold;
  }

  p {
    @apply mt-1 mb-0 text-sm leading-5 text-slate-500 dark:text-slate-400;
  }
}

.forward-panel__counter {
  @apply shrink-0 px-2.5 py-1 text-xs font-medium rounded-full bg-hub-50 text-hub-700 dark:bg-hub-900/40 dark:text-hub-200;
}

.forward-panel__search {
  @apply flex items-center gap-2 mx-6 my-4 px-3 h-11 rounded-xl border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/60 text-slate-500;

  input {
    @apply flex-1 min-w-0 h-full m-0 p-0 border-0 bg-transparent shadow-none text-sm text-slate-800 dark:text-slate-100;

    &:focus {
      @apply outline-none ring-0;
    }
  }
}

.forward-panel__list {
  @apply flex-1 overflow-y-auto px-3 pb-3;
  scrollbar-width: thin;
}

.forward-contact {
  @apply w-full flex items-center gap-3 px-3 py-2.5 mb-1 rounded-xl border border-transparent text-left bg-transparent transition-colors;

  &:hover {
    @apply bg-slate-50 dark:bg-slate-800/70;
  }

  &.is-selected {
    @apply bg-hub-50/80 border-hub-200 dark:bg-hub-900/30 dark:border-hub-700;
  }
}

.forward-contact__check {
  @apply flex items-center justify-center w-6 text-slate-400;

  .is-selected & {
    @apply text-hub-600 dark:text-hub-300;
  }
}

.forward-contact__identity {
  @apply flex flex-col flex-1 min-w-0;

  strong {
    @apply truncate text-sm font-medium text-slate-800 dark:text-slate-100;
  }

  small {
    @apply truncate text-xs text-slate-500 dark:text-slate-400;
  }
}

.forward-contact__activity {
  @apply shrink-0 text-xs text-slate-400 dark:text-slate-500;
}

.forward-panel__empty {
  @apply flex flex-col items-center justify-center gap-1 min-h-[16rem] text-center text-slate-400;

  strong {
    @apply mt-2 text-sm text-slate-600 dark:text-slate-300;
  }

  span {
    @apply text-xs;
  }
}

.forward-panel__footer {
  @apply flex items-center justify-between gap-4 px-6 py-4 border-t border-slate-100 dark:border-slate-800 bg-white dark:bg-slate-900;
}

.forward-panel__hint {
  @apply text-xs leading-4 text-slate-500 dark:text-slate-400;
}

.forward-panel__actions {
  @apply flex items-center gap-2 shrink-0;
}

@media (max-width: 640px) {
  .forward-panel {
    min-width: 100%;
    width: 100%;
  }

  .forward-panel__footer {
    @apply flex-col items-stretch;
  }

  .forward-panel__actions {
    @apply justify-end;
  }

  .forward-contact__activity {
    @apply hidden;
  }
}
</style>
