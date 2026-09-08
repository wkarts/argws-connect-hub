<script setup>
import { computed } from 'vue';
import IntegrationSettingsLayout from '../Layout.vue';
import EmptyState from './EmptyState.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';

const isSetup = computed(() => {
  return false;
});
</script>

<template>
  <IntegrationSettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="$t('INTEGRATION_SETTINGS.CAPTAIN.TITLE')"
        :description="$t('INTEGRATION_SETTINGS.CAPTAIN.DESCRIPTION')"
        :link-text="$t('INTEGRATION_SETTINGS.CAPTAIN.LEARN_MORE')"
        feature-name="captain"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      >
        <template #actions>
          <hub-button
            v-if="isSetup"
            class="rounded-md button nice"
            icon="plus-sign"
          >
            {{ $t('INTEGRATION_SETTINGS.CAPTAIN.HEADER_BTN_TXT') }}
          </hub-button>
        </template>
      </BaseSettingsHeader>
    </template>
    <EmptyState v-if="!isSetup">
      <p class="max-w-xs text-sm font-medium text-center">
        {{ $t('INTEGRATION_SETTINGS.CAPTAIN.LIST.EMPTY_STATE') }}
      </p>
      <hub-button class="px-5 mt-4 rounded-xl" icon="plus-sign">
        {{ $t('INTEGRATION_SETTINGS.CAPTAIN.LIST.CONFIGURE') }}
      </hub-button>
    </EmptyState>
  </IntegrationSettingsLayout>
</template>
