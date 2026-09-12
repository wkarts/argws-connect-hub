import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import * as types from '../mutation-types';
import { INBOX_TYPES } from 'shared/mixins/inboxMixin';
import InboxesAPI from '../../api/inboxes';
import WebChannel from '../../api/channel/webChannel';
import FBChannel from '../../api/channel/fbChannel';
import TwilioChannel from '../../api/channel/twilioChannel';
import { throwErrorMessage } from '../utils/api';

const buildInboxData = inboxParams => {
  const formData = new FormData();
  const { channel = {}, ...inboxProperties } = inboxParams;
  Object.keys(inboxProperties).forEach(key => {
    formData.append(key, inboxProperties[key]);
  });
  const { selectedFeatureFlags, ...channelParams } = channel;
  if (selectedFeatureFlags) {
    if (selectedFeatureFlags.length) {
      selectedFeatureFlags.forEach(featureFlag => {
        formData.append(`channel[selected_feature_flags][]`, featureFlag);
      });
    } else {
      formData.append('channel[selected_feature_flags][]', '');
    }
  }
  Object.keys(channelParams).forEach(key => {
    formData.append(`channel[${key}]`, channel[key]);
  });
  return formData;
};

const legacyOutboundCampaignInbox = inbox => {
  if (
    [
      INBOX_TYPES.API,
      INBOX_TYPES.EMAIL,
      INBOX_TYPES.SMS,
      INBOX_TYPES.WHATSAPP,
    ].includes(inbox.channel_type)
  ) {
    return true;
  }

  return (
    inbox.channel_type === INBOX_TYPES.TWILIO &&
    ['sms', 'whatsapp'].includes(inbox.medium)
  );
};

const supportsCampaignMode = (inbox, mode) => {
  const modes = inbox?.campaign_capabilities?.modes;
  if (Array.isArray(modes)) return modes.includes(mode);

  if (mode === 'one_off') return legacyOutboundCampaignInbox(inbox);
  if (mode === 'ongoing') {
    return inbox.channel_type === INBOX_TYPES.WEB || legacyOutboundCampaignInbox(inbox);
  }
  return false;
};

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
    isUpdatingIMAP: false,
    isUpdatingSMTP: false,
  },
};

export const getters = {
  getInboxes($state) {
    return $state.records;
  },
  getWhatsAppTemplates: $state => (inboxId, openingOnly = false) => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );

    const {
      message_templates: whatsAppMessageTemplates,
      additional_attributes: additionalAttributes,
    } = inbox || {};

    const { message_templates: apiInboxMessageTemplates } =
      additionalAttributes || {};
    const messagesTemplates =
      inbox?.provider === 'connectapi' && openingOnly
        ? inbox.opening_templates || []
        : whatsAppMessageTemplates || apiInboxMessageTemplates;

    if (messagesTemplates instanceof Array) {
      return messagesTemplates.filter(template => {
        return Array.isArray(template.components) && !template.components.some(
          i => i.format === 'IMAGE' || i.format === 'VIDEO'
        );
      });
    }
    return [];
  },
  getWhatsAppCampaignTemplates: ($state, $getters) => inboxId => {
    const inbox = $state.records.find(record => record.id === Number(inboxId));
    const templates = $getters.getWhatsAppTemplates(inboxId, false);

    return templates.filter(template => {
      const status = String(template.status || 'APPROVED').toUpperCase();
      const enabled = ![false, 0, 'false', '0'].includes(template.enabled);
      const available = ![false, 0, 'false', '0'].includes(template.available);
      const approved = status === 'APPROVED';

      if (inbox?.provider === 'connectapi') {
        return (
          approved &&
          enabled &&
          available &&
          template.hub_remote_present === true &&
          template.hub_remote_available === true
        );
      }

      return approved && enabled && available;
    });
  },
  getCampaignInboxes($state) {
    return $state.records.filter(item => supportsCampaignMode(item, 'one_off'));
  },
  getRecurringCampaignInboxes($state) {
    return $state.records.filter(item => supportsCampaignMode(item, 'ongoing'));
  },
  getNewConversationInboxes($state) {
    return $state.records.filter(inbox => {
      const { channel_type: channelType, phone_number: phoneNumber = '' } =
        inbox;

      const isEmailChannel = channelType === INBOX_TYPES.EMAIL;
      const isSmsChannel =
        channelType === INBOX_TYPES.TWILIO &&
        phoneNumber.startsWith('whatsapp');
      return isEmailChannel || isSmsChannel;
    });
  },
  getInbox: $state => inboxId => {
    const [inbox] = $state.records.filter(
      record => record.id === Number(inboxId)
    );
    return inbox || {};
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getWebsiteInboxes($state) {
    return $state.records.filter(item => item.channel_type === INBOX_TYPES.WEB);
  },
  getTwilioInboxes($state) {
    return $state.records.filter(
      item => item.channel_type === INBOX_TYPES.TWILIO
    );
  },
  getSMSInboxes($state) {
    return $state.records.filter(
      item =>
        item.channel_type === INBOX_TYPES.SMS ||
        (item.channel_type === INBOX_TYPES.TWILIO && item.medium === 'sms')
    );
  },
  dialogFlowEnabledInboxes($state) {
    return $state.records.filter(
      item => item.channel_type !== INBOX_TYPES.EMAIL
    );
  },
};

export const actions = {
  setOpeningTemplate: async ({ commit, getters: inboxGetters }, { inboxId, ...attributes }) => {
    const { data } = await InboxesAPI.setOpeningTemplate(inboxId, attributes);
    commit(types.default.EDIT_INBOXES, {
      ...inboxGetters.getInbox(inboxId),
      message_templates: data.message_templates,
      opening_templates: data.opening_templates,
    });
    return data;
  },
  revalidate: async ({ commit }, { newKey }) => {
    try {
      const isExistingKeyValid = await InboxesAPI.validateCacheKey(newKey);
      if (!isExistingKeyValid) {
        const response = await InboxesAPI.refetchAndCommit(newKey);
        commit(types.default.SET_INBOXES, response.data.payload);
      }
    } catch (error) {
      // Ignore error
    }
  },
  get: async ({ commit }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: true });
    try {
      const response = await InboxesAPI.get(true);
      commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: false });
      commit(types.default.SET_INBOXES, response.data.payload);
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isFetching: false });
    }
  },
  createChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WebChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return response.data;
    } catch (error) {
      const errorMessage = error?.response?.data?.message;
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw new Error(errorMessage);
    }
  },
  createWebsiteChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await WebChannel.create(buildInboxData(params));
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return throwErrorMessage(error);
    }
  },
  createTwilioChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await TwilioChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw new Error(error);
    }
  },
  createFBChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await FBChannel.create(params);
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw new Error(error);
    }
  },
  updateInbox: async ({ commit }, { id, formData = true, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: true });
    try {
      const response = await InboxesAPI.update(
        id,
        formData ? buildInboxData(inboxParams) : inboxParams
      );
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdating: false });
      throwErrorMessage(error);
    }
  },
  updateInboxIMAP: async ({ commit }, { id, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: true });
    try {
      const response = await InboxesAPI.update(id, inboxParams);
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingIMAP: false });
      throwErrorMessage(error);
    }
  },
  updateInboxSMTP: async ({ commit }, { id, ...inboxParams }) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: true });
    try {
      const response = await InboxesAPI.update(id, inboxParams);
      commit(types.default.EDIT_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isUpdatingSMTP: false });
      throwErrorMessage(error);
    }
  },
  delete: async ({ commit }, inboxId) => {
    commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: true });
    try {
      await InboxesAPI.delete(inboxId);
      commit(types.default.DELETE_INBOXES, inboxId);
      commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: false });
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isDeleting: false });
      throw new Error(error);
    }
  },
  reauthorizeFacebookPage: async ({ commit }, params) => {
    try {
      const response = await FBChannel.reauthorizeFacebookPage(params);
      commit(types.default.EDIT_INBOXES, response.data);
    } catch (error) {
      throw new Error(error.message);
    }
  },
  deleteInboxAvatar: async (_, inboxId) => {
    try {
      await InboxesAPI.deleteInboxAvatar(inboxId);
    } catch (error) {
      throw new Error(error);
    }
  },
};

export const mutations = {
  [types.default.SET_INBOXES_UI_FLAG]($state, uiFlag) {
    $state.uiFlags = { ...$state.uiFlags, ...uiFlag };
  },
  [types.default.SET_INBOXES]: MutationHelpers.set,
  [types.default.SET_INBOXES_ITEM]: MutationHelpers.setSingleRecord,
  [types.default.ADD_INBOXES]: MutationHelpers.create,
  [types.default.EDIT_INBOXES]: MutationHelpers.update,
  [types.default.DELETE_INBOXES]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
