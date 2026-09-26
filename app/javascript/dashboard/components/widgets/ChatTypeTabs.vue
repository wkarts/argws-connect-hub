<script setup>
import { computed } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import hubConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  activeTab: {
    type: String,
    default: hubConstants.ASSIGNEE_TYPE.ME,
  },
});

const emit = defineEmits(['chatTabChange']);

const activeTabIndex = computed(() => {
  return props.items.findIndex(item => item.key === props.activeTab);
});

const onTabChange = selectedTabIndex => {
  if (!props.items[selectedTabIndex]) return;
  if (props.items[selectedTabIndex].key !== props.activeTab) {
    emit('chatTabChange', props.items[selectedTabIndex].key);
  }
};

const keyboardEvents = {
  'Alt+KeyN': {
    action: () => {
      if (props.items.length) {
        onTabChange((activeTabIndex.value + 1) % props.items.length);
      }
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <hub-tabs
    :index="activeTabIndex"
    class="w-full px-4 py-0 tab--chat-type"
    :class="{ 'tab--chat-type-four': items.length === 4 }"
    @change="onTabChange"
  >
    <hub-tabs-item
      v-for="item in items"
      :key="item.key"
      :name="item.name"
      :count="item.count"
    />
  </hub-tabs>
</template>

<style scoped lang="scss">
.tab--chat-type {
  ::v-deep {
    .tabs {
      @apply p-0;
    }
  }
}

.tab--chat-type-four {
  ::v-deep {
    .tabs {
      width: 100%;
    }

    .tabs > * {
      min-width: 0;
      flex: 1 1 25%;
    }

    .tabs button,
    .tabs [role='tab'] {
      min-width: 0;
      padding-left: 0.25rem;
      padding-right: 0.25rem;
    }
  }
}
</style>
