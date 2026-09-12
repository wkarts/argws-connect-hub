<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import HubMessageEditor from 'dashboard/components/widgets/HubWriter/Editor.vue';
import { useCampaign } from 'shared/composables/useCampaign';
import { INBOX_TYPES } from 'shared/mixins/inboxMixin';
import { URLPattern } from 'urlpattern-polyfill';

export default {
  components: { HubMessageEditor },
  props: {
    selectedCampaign: {
      type: Object,
      default: () => ({}),
    },
  },
  setup() {
    const { isOngoingType, isOneOffType } = useCampaign();
    return { v$: useVuelidate(), isOngoingType, isOneOffType };
  },
  data() {
    return {
      title: '',
      message: '',
      selectedSender: 0,
      selectedInbox: null,
      selectedTemplateKey: '',
      templateParameters: {},
      emailSubject: '',
      endPoint: '',
      timeOnPage: 10,
      triggerOnlyDuringBusinessHours: false,
      enabled: true,
      senderList: [],
    };
  },
  validations() {
    const common = {
      title: { required },
      message: { required },
      selectedInbox: { required },
    };

    if (this.isOngoingType) {
      return {
        ...common,
        selectedSender: { required },
        endPoint: {
          required,
          shouldBeAValidURLPattern(value) {
            try {
              // eslint-disable-next-line no-new
              new URLPattern(value);
              return true;
            } catch (error) {
              return false;
            }
          },
          shouldStartWithHTTP(value) {
            if (!value) return false;
            return value.startsWith('https://') || value.startsWith('http://');
          },
        },
        timeOnPage: { required },
      };
    }

    const oneOff = { ...common };
    if (this.isWhatsAppCampaign) {
      oneOff.selectedTemplateKey = { required };
      oneOff.templateParameters = {
        allRequired() {
          return this.templateVariableIndexes.every(position => {
            const value = this.templateParameters[String(position)];
            return typeof value === 'string' && value.trim().length > 0;
          });
        },
      };
    }
    if (this.isEmailCampaign) oneOff.emailSubject = { required };
    return oneOff;
  },
  computed: {
    ...mapGetters({
      uiFlags: 'campaigns/getUIFlags',
    }),
    inboxes() {
      if (this.isOngoingType) {
        return this.$store.getters['inboxes/getWebsiteInboxes'];
      }
      return this.$store.getters['inboxes/getCampaignInboxes'];
    },
    selectedInboxRecord() {
      if (!this.selectedInbox) return {};
      return this.$store.getters['inboxes/getInbox'](this.selectedInbox);
    },
    isWhatsAppCampaign() {
      return (
        this.isOneOffType &&
        this.selectedInboxRecord.channel_type === INBOX_TYPES.WHATSAPP
      );
    },
    isEmailCampaign() {
      return (
        this.isOneOffType &&
        this.selectedInboxRecord.channel_type === INBOX_TYPES.EMAIL
      );
    },
    isApiCampaign() {
      return (
        this.isOneOffType &&
        this.selectedInboxRecord.channel_type === INBOX_TYPES.API
      );
    },
    whatsAppTemplates() {
      if (!this.isWhatsAppCampaign) return [];
      return this.$store.getters['inboxes/getWhatsAppCampaignTemplates'](
        this.selectedInbox
      );
    },
    selectedTemplate() {
      return this.whatsAppTemplates.find(
        template => this.templateKey(template) === this.selectedTemplateKey
      );
    },
    templateVariableIndexes() {
      if (!this.selectedTemplate) return [];
      const body = (this.selectedTemplate.components || []).find(
        component => component.type === 'BODY'
      );
      if (!body?.text) return [];

      const positions = [];
      const pattern = /\{\{([1-9]\d*)\}\}/g;
      let match = pattern.exec(body.text);
      while (match) {
        positions.push(Number(match[1]));
        match = pattern.exec(body.text);
      }
      return [...new Set(positions)].sort((a, b) => a - b);
    },
    pageTitle() {
      return `${this.$t('CAMPAIGN.EDIT.TITLE')} - ${this.selectedCampaign.title}`;
    },
    sendersAndBotList() {
      return [{ id: 0, name: 'Bot' }, ...this.senderList];
    },
  },
  mounted() {
    this.setFormValues();
  },
  methods: {
    onClose() {
      this.$emit('onClose');
    },
    async loadInboxMembers() {
      if (!this.isOngoingType) return;
      try {
        const response = await this.$store.dispatch('inboxMembers/get', {
          inboxId: this.selectedInbox,
        });
        this.senderList = response.data.payload;
      } catch (error) {
        const errorMessage =
          error?.response?.message || this.$t('CAMPAIGN.ADD.API.ERROR_MESSAGE');
        useAlert(errorMessage);
      }
    },
    onChangeInbox() {
      this.selectedTemplateKey = '';
      this.templateParameters = {};
      this.emailSubject = '';
      if (this.isOneOffType) this.message = '';
      this.loadInboxMembers();
    },
    templateKey(template) {
      return `${template.name}::${template.language}`;
    },
    templateLabel(template) {
      const category = template.category ? ` · ${template.category}` : '';
      return `${template.name} (${template.language})${category}`;
    },
    onTemplateChange() {
      const parameters = {};
      this.templateVariableIndexes.forEach(position => {
        parameters[String(position)] = '';
      });
      this.templateParameters = parameters;
      this.updateTemplateMessage();
    },
    updateTemplateMessage() {
      if (!this.selectedTemplate) return;
      const order = ['HEADER', 'BODY', 'FOOTER'];
      this.message = [...(this.selectedTemplate.components || [])]
        .filter(component => component?.text)
        .sort(
          (left, right) =>
            order.indexOf(left.type) - order.indexOf(right.type)
        )
        .map(component =>
          component.text.replace(/\{\{([1-9]\d*)\}\}/g, (match, position) => {
            const value = this.templateParameters[String(position)];
            return typeof value === 'string' && value.length ? value : match;
          })
        )
        .join('\n\n');
    },
    whatsappTemplateParams() {
      if (!this.selectedTemplate) return {};
      const params = {
        name: this.selectedTemplate.name,
        language: this.selectedTemplate.language,
        category: this.selectedTemplate.category,
        namespace: this.selectedTemplate.namespace,
        processed_params: { ...this.templateParameters },
      };
      if (Number.isInteger(this.selectedTemplate.version)) {
        params.connect_api_version = this.selectedTemplate.version;
      }
      return params;
    },
    getMessageAttributes() {
      if (this.isWhatsAppCampaign) {
        return { template_params: this.whatsappTemplateParams() };
      }
      if (this.isEmailCampaign) return { subject: this.emailSubject };
      if (this.isApiCampaign) return { payload_type: 'message_created' };
      return {};
    },
    setFormValues() {
      const campaign = this.selectedCampaign;
      const rules = campaign.trigger_rules || {};
      const attributes = campaign.message_attributes || {};
      const templateParams = attributes.template_params || {};

      this.title = campaign.title;
      this.message = campaign.message;
      this.endPoint = rules.url || '';
      this.timeOnPage = rules.time_on_page || 10;
      this.selectedInbox = campaign.inbox?.id || null;
      this.triggerOnlyDuringBusinessHours =
        campaign.trigger_only_during_business_hours;
      this.selectedSender = campaign.sender?.id || 0;
      this.enabled = campaign.enabled;
      this.emailSubject = attributes.subject || '';
      this.templateParameters = { ...(templateParams.processed_params || {}) };
      if (templateParams.name && templateParams.language) {
        this.selectedTemplateKey = `${templateParams.name}::${templateParams.language}`;
      }
      this.loadInboxMembers();
    },
    async editCampaign() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      try {
        const payload = {
          id: this.selectedCampaign.id,
          title: this.title,
          message: this.message,
          inbox_id: this.selectedInbox,
        };

        if (this.isOngoingType) {
          Object.assign(payload, {
            trigger_only_during_business_hours:
              this.triggerOnlyDuringBusinessHours,
            sender_id: this.selectedSender || null,
            enabled: this.enabled,
            trigger_rules: {
              url: this.endPoint,
              time_on_page: this.timeOnPage,
            },
          });
        } else {
          payload.message_attributes = this.getMessageAttributes();
        }

        await this.$store.dispatch('campaigns/update', payload);
        useAlert(this.$t('CAMPAIGN.EDIT.API.SUCCESS_MESSAGE'));
        this.onClose();
      } catch (error) {
        const errorMessage =
          error?.response?.data?.message ||
          this.$t('CAMPAIGN.EDIT.API.ERROR_MESSAGE');
        useAlert(errorMessage);
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <hub-modal-header :header-title="pageTitle" />
    <form class="flex flex-col w-full" @submit.prevent="editCampaign">
      <div class="w-full">
        <hub-input
          v-model="title"
          :label="$t('CAMPAIGN.ADD.FORM.TITLE.LABEL')"
          type="text"
          :class="{ error: v$.title.$error }"
          :error="v$.title.$error ? $t('CAMPAIGN.ADD.FORM.TITLE.ERROR') : ''"
          :placeholder="$t('CAMPAIGN.ADD.FORM.TITLE.PLACEHOLDER')"
          @blur="v$.title.$touch"
        />

        <label :class="{ error: v$.selectedInbox.$error }">
          {{ $t('CAMPAIGN.ADD.FORM.INBOX.LABEL') }}
          <select v-model="selectedInbox" @change="onChangeInbox">
            <option v-for="item in inboxes" :key="item.id" :value="item.id">
              {{ item.name }}
            </option>
          </select>
          <span v-if="v$.selectedInbox.$error" class="message">
            {{ $t('CAMPAIGN.ADD.FORM.INBOX.ERROR') }}
          </span>
        </label>

        <div v-if="isOngoingType" class="editor-wrap">
          <label>{{ $t('CAMPAIGN.ADD.FORM.MESSAGE.LABEL') }}</label>
          <HubMessageEditor
            v-model="message"
            class="message-editor"
            is-format-mode
            :class="{ editor_warning: v$.message.$error }"
            :placeholder="$t('CAMPAIGN.ADD.FORM.MESSAGE.PLACEHOLDER')"
            @input="v$.message.$touch"
          />
          <span v-if="v$.message.$error" class="editor-warning__message">
            {{ $t('CAMPAIGN.ADD.FORM.MESSAGE.ERROR') }}
          </span>
        </div>

        <template v-else>
          <label
            v-if="isWhatsAppCampaign"
            :class="{ error: v$.selectedTemplateKey.$error }"
          >
            Template WhatsApp
            <select v-model="selectedTemplateKey" @change="onTemplateChange">
              <option disabled value="">Selecione um template</option>
              <option
                v-for="template in whatsAppTemplates"
                :key="templateKey(template)"
                :value="templateKey(template)"
              >
                {{ templateLabel(template) }}
              </option>
            </select>
            <span v-if="v$.selectedTemplateKey.$error" class="message">
              Selecione um template disponível nesta caixa.
            </span>
          </label>

          <div v-if="isWhatsAppCampaign && templateVariableIndexes.length">
            <label
              v-for="position in templateVariableIndexes"
              :key="position"
            >
              Variável {{ position }}
              <input
                v-model="templateParameters[String(position)]"
                type="text"
                @input="updateTemplateMessage"
                @blur="v$.templateParameters.$touch"
              />
            </label>
            <span v-if="v$.templateParameters.$error" class="message">
              Preencha todas as variáveis do template.
            </span>
          </div>

          <hub-input
            v-if="isEmailCampaign"
            v-model="emailSubject"
            label="Assunto do e-mail"
            type="text"
            :class="{ error: v$.emailSubject.$error }"
            :error="v$.emailSubject.$error ? 'Informe o assunto do e-mail.' : ''"
            @blur="v$.emailSubject.$touch"
          />

          <label :class="{ error: v$.message.$error }">
            {{ isApiCampaign ? 'Payload / mensagem' : $t('CAMPAIGN.ADD.FORM.MESSAGE.LABEL') }}
            <textarea
              v-model="message"
              rows="6"
              :readonly="isWhatsAppCampaign"
              @blur="v$.message.$touch"
            />
            <span v-if="v$.message.$error" class="message">
              {{ $t('CAMPAIGN.ADD.FORM.MESSAGE.ERROR') }}
            </span>
          </label>
        </template>

        <template v-if="isOngoingType">
          <label :class="{ error: v$.selectedSender.$error }">
            {{ $t('CAMPAIGN.ADD.FORM.SENT_BY.LABEL') }}
            <select v-model="selectedSender">
              <option
                v-for="sender in sendersAndBotList"
                :key="sender.name"
                :value="sender.id"
              >
                {{ sender.name }}
              </option>
            </select>
            <span v-if="v$.selectedSender.$error" class="message">
              {{ $t('CAMPAIGN.ADD.FORM.SENT_BY.ERROR') }}
            </span>
          </label>

          <hub-input
            v-model="endPoint"
            :label="$t('CAMPAIGN.ADD.FORM.END_POINT.LABEL')"
            type="text"
            :class="{ error: v$.endPoint.$error }"
            :error="v$.endPoint.$error ? $t('CAMPAIGN.ADD.FORM.END_POINT.ERROR') : ''"
            :placeholder="$t('CAMPAIGN.ADD.FORM.END_POINT.PLACEHOLDER')"
            @blur="v$.endPoint.$touch"
          />
          <hub-input
            v-model="timeOnPage"
            :label="$t('CAMPAIGN.ADD.FORM.TIME_ON_PAGE.LABEL')"
            type="text"
            :class="{ error: v$.timeOnPage.$error }"
            :error="v$.timeOnPage.$error ? $t('CAMPAIGN.ADD.FORM.TIME_ON_PAGE.ERROR') : ''"
            :placeholder="$t('CAMPAIGN.ADD.FORM.TIME_ON_PAGE.PLACEHOLDER')"
            @blur="v$.timeOnPage.$touch"
          />
          <label>
            <input v-model="enabled" type="checkbox" value="enabled" name="enabled" />
            {{ $t('CAMPAIGN.ADD.FORM.ENABLED') }}
          </label>
          <label>
            <input
              v-model="triggerOnlyDuringBusinessHours"
              type="checkbox"
              value="triggerOnlyDuringBusinessHours"
              name="triggerOnlyDuringBusinessHours"
            />
            {{ $t('CAMPAIGN.ADD.FORM.TRIGGER_ONLY_BUSINESS_HOURS') }}
          </label>
        </template>
      </div>

      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <hub-button :is-loading="uiFlags.isCreating">
          {{ $t('CAMPAIGN.EDIT.UPDATE_BUTTON_TEXT') }}
        </hub-button>
        <hub-button variant="clear" @click.prevent="onClose">
          {{ $t('CAMPAIGN.ADD.CANCEL_BUTTON_TEXT') }}
        </hub-button>
      </div>
    </form>
  </div>
</template>

<style lang="scss" scoped>
::v-deep .ProseMirror-hub-style {
  height: 5rem;
}

.message-editor {
  @apply px-3;

  ::v-deep {
    .ProseMirror-menubar {
      @apply rounded-tl-[4px];
    }
  }
}
</style>
