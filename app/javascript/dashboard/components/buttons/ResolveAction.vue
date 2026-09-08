<script setup>
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useToggle } from '@vueuse/core';
import { useI18n } from 'dashboard/composables/useI18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useEmitter } from 'dashboard/composables/emitter';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';

import HubDropdownItem from 'shared/components/ui/dropdown/DropdownItem.vue';
import HubDropdownMenu from 'shared/components/ui/dropdown/DropdownMenu.vue';
import hubConstants from 'dashboard/constants/globals';
import {
  CMD_REOPEN_CONVERSATION,
  CMD_RESOLVE_CONVERSATION,
} from 'dashboard/helper/commandbar/events';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const arrowDownButtonRef = ref(null);
const isLoading = ref(false);

const [showActionsDropdown, toggleDropdown] = useToggle();
const closeDropdown = () => toggleDropdown(false);
const openDropdown = () => toggleDropdown(true);

const currentChat = computed(() => getters.getSelectedChat.value);

const isOpen = computed(
  () => currentChat.value.status === hubConstants.STATUS_TYPE.OPEN
);
const isPending = computed(
  () => currentChat.value.status === hubConstants.STATUS_TYPE.PENDING
);
const isResolved = computed(
  () => currentChat.value.status === hubConstants.STATUS_TYPE.RESOLVED
);
const isSnoozed = computed(
  () => currentChat.value.status === hubConstants.STATUS_TYPE.SNOOZED
);

const buttonClass = computed(() => {
  if (isPending.value) return 'primary';
  if (isOpen.value) return 'success';
  if (isResolved.value) return 'warning';
  return '';
});

const showAdditionalActions = computed(
  () => !isPending.value && !isSnoozed.value
);

const showOpenButton = computed(() => {
  return isPending.value || isSnoozed.value;
});

const getConversationParams = () => {
  const allConversations = document.querySelectorAll(
    '.conversations-list .conversation'
  );

  const activeConversation = document.querySelector(
    'div.conversations-list div.conversation.active'
  );
  const activeConversationIndex = [...allConversations].indexOf(
    activeConversation
  );
  const lastConversationIndex = allConversations.length - 1;

  return {
    all: allConversations,
    activeIndex: activeConversationIndex,
    lastIndex: lastConversationIndex,
  };
};

const openSnoozeModal = () => {
  const ninja = document.querySelector('ninja-keys');
  ninja.open({ parent: 'snooze_conversation' });
};

const toggleStatus = (status, snoozedUntil) => {
  closeDropdown();
  isLoading.value = true;
  store
    .dispatch('toggleStatus', {
      conversationId: currentChat.value.id,
      status,
      snoozedUntil,
    })
    .then(() => {
      useAlert(t('CONVERSATION.CHANGE_STATUS'));
      isLoading.value = false;
    });
};

const onCmdOpenConversation = () => {
  toggleStatus(hubConstants.STATUS_TYPE.OPEN);
};

const onCmdResolveConversation = () => {
  toggleStatus(hubConstants.STATUS_TYPE.RESOLVED);
};

const keyboardEvents = {
  'Alt+KeyM': {
    action: () => arrowDownButtonRef.value?.$el.click(),
    allowOnFocusedInput: true,
  },
  'Alt+KeyE': {
    action: async () => {
      await toggleStatus(hubConstants.STATUS_TYPE.RESOLVED);
    },
  },
  '$mod+Alt+KeyE': {
    action: async event => {
      const { all, activeIndex, lastIndex } = getConversationParams();
      await toggleStatus(hubConstants.STATUS_TYPE.RESOLVED);

      if (activeIndex < lastIndex) {
        all[activeIndex + 1].click();
      } else if (all.length > 1) {
        all[0].click();
        document.querySelector('.conversations-list').scrollTop = 0;
      }
      event.preventDefault();
    },
  },
};

useKeyboardEvents(keyboardEvents);

useEmitter(CMD_REOPEN_CONVERSATION, onCmdOpenConversation);
useEmitter(CMD_RESOLVE_CONVERSATION, onCmdResolveConversation);
</script>

<template>
  <div class="relative flex items-center justify-end resolve-actions">
    <div class="button-group">
      <hub-button
        v-if="isOpen"
        class-names="resolve"
        color-scheme="success"
        icon="checkmark"
        emoji="✅"
        :is-loading="isLoading"
        @click="onCmdResolveConversation"
      >
        {{ $t('CONVERSATION.HEADER.RESOLVE_ACTION') }}
      </hub-button>
      <hub-button
        v-else-if="isResolved"
        class-names="resolve"
        color-scheme="warning"
        icon="arrow-redo"
        emoji="👀"
        :is-loading="isLoading"
        @click="onCmdOpenConversation"
      >
        {{ t('CONVERSATION.HEADER.REOPEN_ACTION') }}
      </hub-button>
      <hub-button
        v-else-if="showOpenButton"
        class-names="resolve"
        color-scheme="primary"
        icon="person"
        :is-loading="isLoading"
        @click="onCmdOpenConversation"
      >
        {{ t('CONVERSATION.HEADER.OPEN_ACTION') }}
      </hub-button>
      <hub-button
        v-if="showAdditionalActions"
        ref="arrowDownButtonRef"
        :color-scheme="buttonClass"
        :disabled="isLoading"
        icon="chevron-down"
        emoji="🔽"
        @click="openDropdown"
      />
    </div>
    <div
      v-if="showActionsDropdown"
      v-on-clickaway="closeDropdown"
      class="dropdown-pane dropdown-pane--open left-auto top-[2.625rem] mt-0.5 right-0 max-w-[12.5rem] min-w-[9.75rem]"
    >
      <HubDropdownMenu class="mb-0">
        <HubDropdownItem v-if="!isPending">
          <hub-button
            variant="clear"
            color-scheme="secondary"
            size="small"
            icon="snooze"
            @click="() => openSnoozeModal()"
          >
            {{ t('CONVERSATION.RESOLVE_DROPDOWN.SNOOZE_UNTIL') }}
          </hub-button>
        </HubDropdownItem>
        <HubDropdownItem v-if="!isPending">
          <hub-button
            variant="clear"
            color-scheme="secondary"
            size="small"
            icon="book-clock"
            @click="() => toggleStatus(hubConstants.STATUS_TYPE.PENDING)"
          >
            {{ t('CONVERSATION.RESOLVE_DROPDOWN.MARK_PENDING') }}
          </hub-button>
        </HubDropdownItem>
      </HubDropdownMenu>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.dropdown-pane {
  .dropdown-menu__item {
    @apply mb-0;
  }
}
</style>
