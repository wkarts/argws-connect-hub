<script setup>
import BaseEmptyState from './BaseEmptyState.vue';

const props = defineProps({
  isSuperAdmin: {
    type: Boolean,
    default: false,
  },
  isOnHubCloud: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['click']);
const i18nKey = props.isOnHubCloud ? 'PAYWALL' : 'ENTERPRISE_PAYWALL';
</script>

<template>
  <BaseEmptyState>
    <div
      class="flex flex-col max-w-md px-6 py-6 bg-white border shadow dark:bg-slate-800 rounded-xl border-slate-100 dark:border-slate-900"
    >
      <div class="flex items-center w-full gap-2 mb-4">
        <span
          class="flex items-center justify-center w-6 h-6 rounded-full bg-hub-75/70 dark:bg-hub-800/40"
        >
          <fluent-icon
            size="14"
            class="flex-shrink-0 text-hub-500 dark:text-hub-500"
            icon="lock-closed"
          />
        </span>
        <span class="text-base font-medium text-slate-900 dark:text-white">
          {{ $t('SLA.PAYWALL.TITLE') }}
        </span>
      </div>
      <p
        class="text-sm font-normal"
        v-html="$t(`SLA.${i18nKey}.AVAILABLE_ON`)"
      />
      <p class="text-sm font-normal">
        {{ $t(`SLA.${i18nKey}.UPGRADE_PROMPT`) }}
        <span v-if="!isOnHubCloud && !isSuperAdmin">
          {{ $t('SLA.ENTERPRISE_PAYWALL.ASK_ADMIN') }}
        </span>
      </p>
      <template v-if="isOnHubCloud || true">
        <hub-button
          color-scheme="primary"
          class="w-full mt-2 text-center rounded-xl"
          size="expanded"
          is-expanded
          @click="emit('click')"
        >
          {{ $t('SLA.PAYWALL.UPGRADE_NOW') }}
        </hub-button>
        <span class="mt-2 text-xs tracking-tight text-center">
          {{ $t('SLA.PAYWALL.CANCEL_ANYTIME') }}
        </span>
      </template>
      <template v-else-if="isSuperAdmin">
        <a href="/super_admin" class="block w-full">
          <hub-button
            color-scheme="primary"
            class="w-full mt-2 text-center rounded-xl"
            size="expanded"
            is-expanded
          >
            {{ $t('SLA.PAYWALL.UPGRADE_NOW') }}
          </hub-button>
        </a>
      </template>
    </div>
  </BaseEmptyState>
</template>
