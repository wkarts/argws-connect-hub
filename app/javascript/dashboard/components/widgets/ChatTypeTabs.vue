<script setup>
import { computed, ref, nextTick } from 'vue';
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
const compactTabs = ref(null);
const moveFocus = index => { onTabChange(index); nextTick(() => compactTabs.value?.querySelectorAll('[role=tab]')[index]?.focus()); };

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
      if (props.items.length) onTabChange((activeTabIndex.value + 1) % props.items.length);
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <div v-if="items.length === 4" ref="compactTabs" class="compact-chat-tabs" role="tablist" :aria-label="$t('CHAT_LIST.TAB_HEADING')">
    <button v-for="(item, index) in items" :key="item.key" type="button" role="tab" :aria-selected="index === activeTabIndex" :tabindex="index === activeTabIndex ? 0 : -1"
      :title="`${item.name}: ${item.count}`" :class="{ 'is-active': index === activeTabIndex }" @click="onTabChange(index)"
      @keydown.right.prevent="moveFocus((index + 1) % items.length)" @keydown.left.prevent="moveFocus((index + items.length - 1) % items.length)" @keydown.home.prevent="moveFocus(0)" @keydown.end.prevent="moveFocus(items.length - 1)">
      <span class="compact-chat-tabs__label">{{ item.name }}</span><span class="compact-chat-tabs__count">{{ item.count > 99 ? '99+' : item.count }}</span>
    </button>
  </div>
  <hub-tabs v-else
    :index="activeTabIndex"
    class="w-full px-4 py-0 tab--chat-type"
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
.compact-chat-tabs { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1.65fr) minmax(0, 1fr) minmax(0, 1fr); width: 100%; padding: 0 8px; border-bottom: 1px solid #e2e8f0; height: 48px; }
.compact-chat-tabs button { display: flex; flex-direction: column; align-items: center; justify-content: center; min-width: 0; gap: 2px; padding: 4px 2px; background: transparent; border: 0; border-bottom: 2px solid transparent; color: #64748b; cursor: pointer; }
.compact-chat-tabs button.is-active { color: #2563eb; border-bottom-color: currentColor; }
.compact-chat-tabs button:focus-visible { outline: 2px solid currentColor; outline-offset: -2px; }
.compact-chat-tabs__label { display: block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 11px; line-height: 15px; font-weight: 500; }
.compact-chat-tabs__count { font-size: 10px; line-height: 13px; padding: 0 4px; border-radius: 4px; background: #f1f5f9; }
.dark .compact-chat-tabs { border-color: #334155; }
.dark .compact-chat-tabs button { color: #cbd5e1; }
.dark .compact-chat-tabs button.is-active { color: #60a5fa; }
.dark .compact-chat-tabs__count { background: #1e293b; }
.tab--chat-type {
  ::v-deep {
    .tabs {
      @apply p-0;
    }
  }
}
</style>
