<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import HubMessageEditor from 'dashboard/components/widgets/HubWriter/Editor.vue';
import { useCampaign } from 'shared/composables/useCampaign';
import { INBOX_TYPES } from 'shared/mixins/inboxMixin';
import HubDateTimePicker from 'dashboard/components/ui/DateTimePicker.vue';
import { URLPattern } from 'urlpattern-polyfill';

export default {
  components: {
    HubDateTimePicker,
    HubMessageEditor,
  },
  setup() {
    const { campaignType, isOngoingType, isOneOffType } = useCampaign();
    return { v$: useVuelidate(), campaignType, isOngoingType, isOneOffType };
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
      show: true,
      enabled: true,
      triggerOnlyDuringBusinessHours: false,
      scheduledAt: null,
      selectedAudience: [],
      senderList: [],
    };
  },

  validations() {
    const commonValidations = {
      title: { required },
      message: { required },
      selectedInbox: { required },
    };

    if (this.isOngoingType) {
      return {
        ...commonValidations,
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

    const oneOffValidations = {
      ...commonValidations,
      selectedAudience: {
        isEmpty() {
          return !!this.selectedAudience.length;
        },
      },
    };

    if (this.isWhatsAppCampaign) {
      oneOffValidations.selectedTemplateKey = { required };
      oneOffValidations.templateParameters = {
        allRequired() {
          return this.templateVariableIndexes.every(position => {
            const value = this.templateParameters[String(position)];
            return typeof value === 'string' && value.trim().length > 0;
          });
        },
      };
    }

    if (this.isEmailCampaign) {
      oneOffValidations.emailSubject = { required };
    }

    return oneOffValidations;
  },
  computed: {
    ...mapGetters({
      uiFlags: 'campaigns/getUIFlags',
      audienceList: 'labels/getLabels',
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
    sendersAndBotList() {
      return [
        { id: 0, name: 'Bot' },
        ...this.senderList,
      ];
    },
  },
  methods: {
    onClose() {
      this.$emit('onClose');
    },
    onChange(value) {
      this.scheduledAt = value;
    },
    async onChangeInbox() {
      this.selectedTemplateKey = '';
      this.templateParameters = {};
      this.emailSubject = '';
      if (this.isOneOffType) this.message = '';

      if (!this.isOngoingType) return;

      try {
        const response = await this.$store.dispatch('inboxMembers/get', {
          inboxId: this.selectedInbox,
        });
        const {
          data: { payload: inboxMembers },
        } = response;
        this.senderList = inboxMembers;
      } catch (error) {
        const errorMessage =
          error?.response?.message || this.$t('CAMPAIGN.ADD.API.ERROR_MESSAGE');
        useAlert(errorMessage);
      }
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
      if (!this.selectedTemplate) {
        this.message = '';
        return;
      }

      const order = ['HEADER', 'BODY', 'FOOTER'];
      const components = [...(this.selectedTemplate.components || [])]
        .filter(component => component?.text)
        .sort(
          (left, right) =>
            order.indexOf(left.type) - order.indexOf(right.type)
        );

      this.message = components
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
      if (this.isEmailCampaign) {
        return { subject: this.emailSubject };
      }
      if (this.isApiCampaign) {
        return { payload_type: 'message_created' };
      }
      return {};
    },
    getCampaignDetails() {
      if (this.isOngoingType) {
        return {
          title: this.title,
          message: this.message,
          inbox_id: this.selectedInbox,
          sender_id: this.selectedSender || null,
          enabled: this.enabled,
          trigger_only_during_business_hours:
            this.triggerOnlyDuringBusinessHours,
          trigger_rules: {
            url: this.endPoint,
            time_on_page: this.timeOnPage,
          },
        };
      }

      const audience = this.selectedAudience.map(item => ({
        id: item.id,
        type: 'Label',
      }));

      return {
        title: this.title,
        message: this.message,
        message_attributes: this.getMessageAttributes(),
        inbox_id: this.selectedInbox,
        scheduled_at: this.scheduledAt,
        audience,
      };
    },
    async addCampaign() {
      this.v$.$touch();
      if (this.v$.$invalid) return;

      try {
        await this.$store.dispatch('campaigns/create', this.getCampaignDetails());
        useAlert(this.$t('CAMPAIGN.ADD.API.SUCCESS_MESSAGE'));
        this.onClose();
      } catch (error) {
        const errorMessage =
          error?.response?.data?.message ||
          error?.response?.message ||
          this.$t('CAMPAIGN.ADD.API.ERROR_MESSAGE');
        useAlert(errorMessage);
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <hub-modal-header
      :header-title="$t('CAMPAIGN.ADD.TITLE')"
      :header-content="$t('CAMPAIGN.ADD.DESC')"
    />
    <form class="flex flex-col w-full" @submit.prevent="addCampaign">
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
            <option disabled :value="null">Selecione uma caixa de saída</option>
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
          <div>
            <HubMessageEditor
              v-model="message"
              class="message-editor"
              :class="{ editor_warning: v$.message.$error }"
              :placeholder="$t('CAMPAIGN.ADD.FORM.MESSAGE.PLACEHOLDER')"
              @blur="v$.message.$touch"
            />
            <span v-if="v$.message.$error" class="editor-warning__message">
              {{ $t('CAMPAIGN.ADD.FORM.MESSAGE.ERROR') }}
            </span>
          </div>
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
                :placeholder="`Valor de {{${position}}}`"
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
            placeholder="Assunto da campanha"
            @blur="v$.emailSubject.$touch"
          />

          <label :class="{ error: v$.message.$error }">
            {{ isApiCampaign ? 'Payload / mensagem' : $t('CAMPAIGN.ADD.FORM.MESSAGE.LABEL') }}
            <textarea
              v-model="message"
              rows="6"
              type="text"
              :readonly="isWhatsAppCampaign"
              :placeholder="
                isApiCampaign
                  ? 'Informe o conteúdo ou JSON que será entregue pelo webhook'
                  : $t('CAMPAIGN.ADD.FORM.MESSAGE.PLACEHOLDER')
              "
              @blur="v$.message.$touch"
            />
            <span v-if="v$.message.$error" class="message">
              {{ $t('CAMPAIGN.ADD.FORM.MESSAGE.ERROR') }}
            </span>
          </label>
        </template>

        <label
          v-if="isOneOffType"
          class="multiselect-wrap--small"
          :class="{ error: v$.selectedAudience.$error }"
        >
          {{ $t('CAMPAIGN.ADD.FORM.AUDIENCE.LABEL') }}
          <multiselect
            v-model="selectedAudience"
            :options="audienceList"
            track-by="id"
            label="title"
            multiple
            :close-on-select="false"
            :clear-on-select="false"
            hide-selected
            :placeholder="$t('CAMPAIGN.ADD.FORM.AUDIENCE.PLACEHOLDER')"
            selected-label
            :select-label="$t('FORMS.MULTISELECT.ENTER_TO_SELECT')"
            :deselect-label="$t('FORMS.MULTISELECT.ENTER_TO_REMOVE')"
            @blur="v$.selectedAudience.$touch"
            @select="v$.selectedAudience.$touch"
          />
          <span v-if="v$.selectedAudience.$error" class="message">
            {{ $t('CAMPAIGN.ADD.FORM.AUDIENCE.ERROR') }}
          </span>
        </label>

        <label
          v-if="isOngoingType"
          :class="{ error: v$.selectedSender.$error }"
        >
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

        <label v-if="isOneOffType">
          {{ $t('CAMPAIGN.ADD.FORM.SCHEDULED_AT.LABEL') }}
          <HubDateTimePicker
            :value="scheduledAt"
            :confirm-text="$t('CAMPAIGN.ADD.FORM.SCHEDULED_AT.CONFIRM')"
            :placeholder="$t('CAMPAIGN.ADD.FORM.SCHEDULED_AT.PLACEHOLDER')"
            @change="onChange"
          />
        </label>

        <hub-input
          v-if="isOngoingType"
          v-model="endPoint"
          :label="$t('CAMPAIGN.ADD.FORM.END_POINT.LABEL')"
          type="text"
          :class="{ error: v$.endPoint.$error }"
          :error="v$.endPoint.$error ? $t('CAMPAIGN.ADD.FORM.END_POINT.ERROR') : ''"
          :placeholder="$t('CAMPAIGN.ADD.FORM.END_POINT.PLACEHOLDER')"
          @blur="v$.endPoint.$touch"
        />
        <hub-input
          v-if="isOngoingType"
          v-model="timeOnPage"
          :label="$t('CAMPAIGN.ADD.FORM.TIME_ON_PAGE.LABEL')"
          type="text"
          :class="{ error: v$.timeOnPage.$error }"
          :error="
            v$.timeOnPage.$error
              ? $t('CAMPAIGN.ADD.FORM.TIME_ON_PAGE.ERROR')
              : ''
          "
          :placeholder="$t('CAMPAIGN.ADD.FORM.TIME_ON_PAGE.PLACEHOLDER')"
          @blur="v$.timeOnPage.$touch"
        />
        <label v-if="isOngoingType">
          <input v-model="enabled" type="checkbox" value="enabled" name="enabled" />
          {{ $t('CAMPAIGN.ADD.FORM.ENABLED') }}
        </label>
        <label v-if="isOngoingType">
          <input
            v-model="triggerOnlyDuringBusinessHours"
            type="checkbox"
            value="triggerOnlyDuringBusinessHours"
            name="triggerOnlyDuringBusinessHours"
          />
          {{ $t('CAMPAIGN.ADD.FORM.TRIGGER_ONLY_BUSINESS_HOURS') }}
        </label>
      </div>

      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <hub-button :is-loading="uiFlags.isCreating">
          {{ $t('CAMPAIGN.ADD.CREATE_BUTTON_TEXT') }}
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
