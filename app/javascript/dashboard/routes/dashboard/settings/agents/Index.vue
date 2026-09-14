<script setup>
import { useAlert } from 'dashboard/composables';
import { computed, onMounted, ref } from 'vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';
import { useI18n } from 'dashboard/composables/useI18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';

import AddAgent from './AddAgent.vue';
import EditAgent from './EditAgent.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();

const loading = ref({});
const showAddPopup = ref(false);
const showDeletePopup = ref(false);
const showEditPopup = ref(false);
const showResetTwoFactorPopup = ref(false);
const agentAPI = ref({ message: '' });
const currentAgent = ref({});

const deleteConfirmText = computed(
  () => `${t('AGENT_MGMT.DELETE.CONFIRM.YES')} ${currentAgent.value.name}`
);
const deleteRejectText = computed(() => {
  return `${t('AGENT_MGMT.DELETE.CONFIRM.NO')} ${currentAgent.value.name}`;
});
const deleteMessage = computed(() => {
  return ` ${currentAgent.value.name}?`;
});
const resetTwoFactorConfirmText = computed(
  () => `${t('AGENT_MGMT.RESET_2FA.CONFIRM.YES')} ${currentAgent.value.name}`
);
const resetTwoFactorRejectText = computed(() =>
  t('AGENT_MGMT.RESET_2FA.CONFIRM.NO')
);
const resetTwoFactorMessage = computed(() => ` ${currentAgent.value.name}?`);

const agentList = computed(() => getters['agents/getAgents'].value);
const uiFlags = computed(() => getters['agents/getUIFlags'].value);
const currentUserId = computed(() => getters.getCurrentUserID.value);

onMounted(() => {
  store.dispatch('agents/get');
});

const verifiedAdministrators = computed(() => {
  return agentList.value.filter(
    agent => agent.role === 'administrator' && agent.confirmed
  );
});

const showEditAction = agent => {
  return currentUserId.value !== agent.id;
};

const showDeleteAction = agent => {
  if (currentUserId.value === agent.id) {
    return false;
  }

  if (!agent.confirmed) {
    return true;
  }

  if (agent.role === 'administrator') {
    return verifiedAdministrators.value.length !== 1;
  }
  return true;
};
const showAlertMessage = message => {
  loading.value[currentAgent.value.id] = false;
  currentAgent.value = {};
  agentAPI.value.message = message;
  useAlert(message);
};

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = agent => {
  showEditPopup.value = true;
  currentAgent.value = agent;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = agent => {
  showDeletePopup.value = true;
  currentAgent.value = agent;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};

const openResetTwoFactorPopup = agent => {
  showResetTwoFactorPopup.value = true;
  currentAgent.value = agent;
};
const closeResetTwoFactorPopup = () => {
  showResetTwoFactorPopup.value = false;
};

const deleteAgent = async id => {
  try {
    await store.dispatch('agents/delete', id);
    showAlertMessage(t('AGENT_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    showAlertMessage(t('AGENT_MGMT.DELETE.API.ERROR_MESSAGE'));
  }
};
const confirmDeletion = () => {
  loading.value[currentAgent.value.id] = true;
  closeDeletePopup();
  deleteAgent(currentAgent.value.id);
};

const resetTwoFactor = async id => {
  try {
    await store.dispatch('agents/resetTwoFactor', id);
    showAlertMessage(t('AGENT_MGMT.RESET_2FA.API.SUCCESS_MESSAGE'));
  } catch (error) {
    showAlertMessage(t('AGENT_MGMT.RESET_2FA.API.ERROR_MESSAGE'));
  }
};
const confirmTwoFactorReset = () => {
  loading.value[currentAgent.value.id] = true;
  closeResetTwoFactorPopup();
  resetTwoFactor(currentAgent.value.id);
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('AGENT_MGMT.LOADING')"
    :no-records-found="!agentList.length"
    :no-records-message="$t('AGENT_MGMT.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('AGENT_MGMT.HEADER')"
        :description="$t('AGENT_MGMT.DESCRIPTION')"
        :link-text="$t('AGENT_MGMT.LEARN_MORE')"
        feature-name="agents"
      >
        <template #actions>
          <hub-button
            class="button nice rounded-md"
            icon="add-circle"
            @click="openAddPopup"
          >
            {{ $t('AGENT_MGMT.HEADER_BTN_TXT') }}
          </hub-button>
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <table class="divide-y divide-slate-75 dark:divide-slate-700">
        <tbody
          class="divide-y divide-slate-50 dark:divide-slate-800 text-slate-700 dark:text-slate-300"
        >
          <tr v-for="agent in agentList" :key="agent.email">
            <td class="py-4 ltr:pr-4 rtl:pl-4">
              <div class="flex items-center flex-row gap-4">
                <Thumbnail
                  :src="agent.thumbnail"
                  :username="agent.name"
                  size="40px"
                  :status="agent.availability_status"
                />
                <div>
                  <span class="block font-medium capitalize">
                    {{ agent.name }}
                  </span>
                  <span>{{ agent.email }}</span>
                </div>
              </div>
            </td>

            <td class="py-4 ltr:pr-4 rtl:pl-4">
              <span class="block font-medium capitalize">
                {{ $t(`AGENT_MGMT.AGENT_TYPES.${agent.role.toUpperCase()}`) }}
              </span>
            </td>
            <td class="py-4 ltr:pr-4 rtl:pl-4">
              <span v-if="agent.confirmed">
                {{ $t('AGENT_MGMT.LIST.VERIFIED') }}
              </span>
              <span v-if="!agent.confirmed">
                {{ $t('AGENT_MGMT.LIST.VERIFICATION_PENDING') }}
              </span>
            </td>
            <td class="py-4">
              <div class="flex justify-end gap-1">
                <hub-button
                  v-if="agent.two_factor_enabled"
                  v-tooltip.top="$t('AGENT_MGMT.RESET_2FA.BUTTON_TEXT')"
                  variant="smooth"
                  size="tiny"
                  color-scheme="alert"
                  class-names="grey-btn"
                  :is-loading="loading[agent.id]"
                  @click="openResetTwoFactorPopup(agent)"
                >
                  2FA
                </hub-button>
                <hub-button
                  v-if="showEditAction(agent)"
                  v-tooltip.top="$t('AGENT_MGMT.EDIT.BUTTON_TEXT')"
                  variant="smooth"
                  size="tiny"
                  color-scheme="secondary"
                  icon="edit"
                  class-names="grey-btn"
                  @click="openEditPopup(agent)"
                />
                <hub-button
                  v-if="showDeleteAction(agent)"
                  v-tooltip.top="$t('AGENT_MGMT.DELETE.BUTTON_TEXT')"
                  variant="smooth"
                  color-scheme="alert"
                  size="tiny"
                  icon="dismiss-circle"
                  class-names="grey-btn"
                  :is-loading="loading[agent.id]"
                  @click="openDeletePopup(agent)"
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </template>

    <hub-modal :show.sync="showAddPopup" :on-close="hideAddPopup">
      <AddAgent :on-close="hideAddPopup" />
    </hub-modal>

    <hub-modal :show.sync="showEditPopup" :on-close="hideEditPopup">
      <EditAgent
        v-if="showEditPopup"
        :id="currentAgent.id"
        :name="currentAgent.name"
        :type="currentAgent.role"
        :email="currentAgent.email"
        :availability="currentAgent.availability_status"
        :on-close="hideEditPopup"
      />
    </hub-modal>

    <hub-delete-modal
      :show.sync="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('AGENT_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('AGENT_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />

    <hub-delete-modal
      :show.sync="showResetTwoFactorPopup"
      :on-close="closeResetTwoFactorPopup"
      :on-confirm="confirmTwoFactorReset"
      :title="$t('AGENT_MGMT.RESET_2FA.CONFIRM.TITLE')"
      :message="$t('AGENT_MGMT.RESET_2FA.CONFIRM.MESSAGE')"
      :message-value="resetTwoFactorMessage"
      :confirm-text="resetTwoFactorConfirmText"
      :reject-text="resetTwoFactorRejectText"
    />
  </SettingsLayout>
</template>
