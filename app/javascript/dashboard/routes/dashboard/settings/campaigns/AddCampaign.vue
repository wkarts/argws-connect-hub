<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import HubMessageEditor from 'dashboard/components/widgets/HubWriter/Editor.vue';
import { useCampaign } from 'shared/composables/useCampaign';
import { INBOX_TYPES } from 'shared/mixins/inboxMixin';
import HubDateTimePicker from 'dashboard/components/ui/DateTimePicker.vue';
import CampaignMaterials from './CampaignMaterials.vue';
import { URLPattern } from 'urlpattern-polyfill';

export default {
  components: {
    HubDateTimePicker,
    HubMessageEditor,
    CampaignMaterials,
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
      whatsappMode: 'freeform',
      selectedTemplateKey: '',
      templateParameters: {},
      emailSubject: '',
      endPoint: '',
      timeOnPage: 10,
      enabled: true,
      triggerOnlyDuringBusinessHours: false,
      scheduledAt: null,
      recurrenceFrequency: 'daily',
      recurrenceInterval: 1,
      recurrenceEndsAt: null,
      materials: [],
      selectedAudience: [],
      senderList: [],
    };
  },
  validations() {
    const validations = {
      title: { required },
      message: {
        hasContent() {
          return Boolean(this.message?.trim() || this.materials.length);
        },
      },
      selectedInbox: { required },
      scheduledAt: { required },
    };

    if (this.isWebsiteCampaign) {
      validations.selectedSender = { required };
      validations.endPoint = {
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
      };
      validations.timeOnPage = { required };
    } else if (this.selectedInbox) {
      validations.selectedAudience = {
        isEmpty() {
          return !!this.selectedAudience.length;
        },
      };
    }

    if (this.isScheduledRecurringCampaign) {
      validations.recurrenceFrequency = { required };
      validations.recurrenceInterval = {
        positive(value) {
          return Number(value) > 0;
        },
      };
    }

    if (this.isWhatsAppTemplateMode) {
      validations.selectedTemplateKey = { required };
      validations.templateParameters = {
        allRequired() {
          return this.templateVariableIndexes.every(position => {
            const value = this.templateParameters[String(position)];
            return typeof value === 'string' && value.trim().length > 0;
          });
        },
      };
    }

    if (this.isEmailCampaign) validations.emailSubject = { required };
    return validations;
  },
  computed: {
    ...mapGetters({
      uiFlags: 'campaigns/getUIFlags',
      audienceList: 'labels/getLabels',
    }),
    inboxes() {
      return this.isOngoingType
        ? this.$store.getters['inboxes/getRecurringCampaignInboxes']
        : this.$store.getters['inboxes/getCampaignInboxes'];
    },
    selectedInboxRecord() {
      if (!this.selectedInbox) return {};
      return this.$store.getters['inboxes/getInbox'](this.selectedInbox);
    },
    isWebsiteCampaign() {
      return (
        this.isOngoingType &&
        this.selectedInboxRecord.channel_type === INBOX_TYPES.WEB
      );
    },
    isScheduledRecurringCampaign() {
      return this.isOngoingType && this.selectedInbox && !this.isWebsiteCampaign;
    },
    isWhatsAppCampaign() {
      return this.selectedInboxRecord.channel_type === INBOX_TYPES.WHATSAPP;
    },
    isWhatsAppTemplateMode() {
      return this.isWhatsAppCampaign && this.whatsappMode === 'template';
    },
    isEmailCampaign() {
      return this.selectedInboxRecord.channel_type === INBOX_TYPES.EMAIL;
    },
    isApiCampaign() {
      return this.selectedInboxRecord.channel_type === INBOX_TYPES.API;
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
      return [{ id: 0, name: 'Bot' }, ...this.senderList];
    },
    audienceHasError() {
      return Boolean(this.v$.selectedAudience && this.v$.selectedAudience.$error);
    },
  },
  methods: {
    onClose() {
      this.$emit('onClose');
    },
    onChange(value) {
      this.scheduledAt = value;
    },
    onRecurrenceEndsAtChange(value) {
      this.recurrenceEndsAt = value;
    },
    touchAudience() {
      if (this.v$.selectedAudience) this.v$.selectedAudience.$touch();
    },
    async onChangeInbox() {
      this.whatsappMode = 'freeform';
      this.selectedTemplateKey = '';
      this.templateParameters = {};
      this.emailSubject = '';
      this.message = '';
      this.senderList = [];

      if (!this.isWebsiteCampaign) return;

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
    onWhatsappModeChange() {
      this.selectedTemplateKey = '';
      this.templateParameters = {};
      this.message = '';
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
        if (this.whatsappMode === 'template') {
          return {
            delivery_mode: 'template',
            template_params: this.whatsappTemplateParams(),
          };
        }
        return { delivery_mode: 'freeform' };
      }
      if (this.isEmailCampaign) return { subject: this.emailSubject };
      if (this.isApiCampaign) return { payload_type: 'message_created' };
      return {};
    },
    recurringTriggerRules() {
      return {
        recurrence: {
          frequency: this.recurrenceFrequency,
          interval: Number(this.recurrenceInterval),
          ends_at: this.recurrenceEndsAt || null,
        },
      };
    },
    getCampaignDetails() {
      const payload = {
        title: this.title,
        message: this.message || '',
        campaign_type: this.campaignType,
        inbox_id: this.selectedInbox,
        scheduled_at: this.scheduledAt,
        message_attributes: this.getMessageAttributes(),
        material_blob_ids: this.materials.map(material => material.signed_id),
      };

      if (this.isWebsiteCampaign) {
        return {
          ...payload,
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

      payload.audience = this.selectedAudience.map(item => ({
        id: item.id,
        type: 'Label',
      }));
      payload.enabled = this.isOngoingType ? this.enabled : true;
      if (this.isScheduledRecurringCampaign) {
        payload.trigger_rules = this.recurringTriggerRules();
      }
      return payload;
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

        <div v-if="isWebsiteCampaign" class="editor-wrap">
          <label>{{ $t('CAMPAIGN.ADD.FORM.MESSAGE.LABEL') }}</label>
          <HubMessageEditor
            v-model="message"
            class="message-editor"
            :class="{ editor_warning: v$.message.$error }"
            :placeholder="$t('CAMPAIGN.ADD.FORM.MESSAGE.PLACEHOLDER')"
            @blur="v$.message.$touch"
          />
        </div>

        <template v-else-if="selectedInbox">
          <label v-if="isWhatsAppCampaign">
            Tipo de mensagem WhatsApp
            <select v-model="whatsappMode" @change="onWhatsappModeChange">
              <option value="freeform">Mensagem livre</option>
              <option value="template">Template</option>
            </select>
          </label>

          <div v-if="isWhatsAppCampaign && whatsappMode === 'freeform'" class="campaign-warning">
            Mensagens livres podem depender da janela de atendimento e das regras da instância/provedor do WhatsApp. A campanha será permitida e o resultado do envio será registrado normalmente.
          </div>

          <label
            v-if="isWhatsAppTemplateMode"
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

          <div v-if="isWhatsAppTemplateMode && templateVariableIndexes.length">
            <label v-for="position in templateVariableIndexes" :key="position">
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
              :readonly="isWhatsAppTemplateMode"
              :placeholder="
                isApiCampaign
                  ? 'Informe o conteúdo ou JSON que será entregue pelo webhook'
                  : $t('CAMPAIGN.ADD.FORM.MESSAGE.PLACEHOLDER')
              "
              @blur="v$.message.$touch"
            />
            <span v-if="v$.message.$error" class="message">
              Informe uma mensagem ou anexe pelo menos um material.
            </span>
          </label>

          <label
            class="multiselect-wrap--small"
            :class="{ error: audienceHasError }"
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
              @blur="touchAudience"
              @select="touchAudience"
            />
            <span v-if="audienceHasError" class="message">
              {{ $t('CAMPAIGN.ADD.FORM.AUDIENCE.ERROR') }}
            </span>
          </label>
        </template>

        <CampaignMaterials v-if="selectedInbox" v-model="materials" />

        <template v-if="isWebsiteCampaign">
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
            <input
              v-model="triggerOnlyDuringBusinessHours"
              type="checkbox"
            />
            {{ $t('CAMPAIGN.ADD.FORM.TRIGGER_ONLY_BUSINESS_HOURS') }}
          </label>
        </template>

        <label :class="{ error: v$.scheduledAt.$error }">
          Data e hora da campanha
          <HubDateTimePicker
            :value="scheduledAt"
            :confirm-text="$t('CAMPAIGN.ADD.FORM.SCHEDULED_AT.CONFIRM')"
            :placeholder="$t('CAMPAIGN.ADD.FORM.SCHEDULED_AT.PLACEHOLDER')"
            @change="onChange"
          />
          <span v-if="v$.scheduledAt.$error" class="message">
            Informe a data e a hora da campanha.
          </span>
        </label>

        <div v-if="isScheduledRecurringCampaign" class="recurrence-grid">
          <label :class="{ error: v$.recurrenceFrequency.$error }">
            Recorrência
            <select v-model="recurrenceFrequency">
              <option value="hourly">Hora(s)</option>
              <option value="daily">Dia(s)</option>
              <option value="weekly">Semana(s)</option>
              <option value="monthly">Mês(es)</option>
            </select>
          </label>
          <label :class="{ error: v$.recurrenceInterval.$error }">
            Repetir a cada
            <input v-model.number="recurrenceInterval" type="number" min="1" step="1" />
            <span v-if="v$.recurrenceInterval.$error" class="message">
              O intervalo deve ser maior que zero.
            </span>
          </label>
          <label>
            Encerrar recorrência em (opcional)
            <HubDateTimePicker
              :value="recurrenceEndsAt"
              :confirm-text="$t('CAMPAIGN.ADD.FORM.SCHEDULED_AT.CONFIRM')"
              placeholder="Sem data de término"
              @change="onRecurrenceEndsAtChange"
            />
          </label>
        </div>

        <label v-if="isOngoingType">
          <input v-model="enabled" type="checkbox" />
          {{ $t('CAMPAIGN.ADD.FORM.ENABLED') }}
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
}

.campaign-warning {
  @apply p-3 mb-3 text-sm rounded border border-yellow-300 bg-yellow-50 text-yellow-900;
}

.recurrence-grid {
  @apply grid grid-cols-1 gap-3 mb-3 md:grid-cols-3;
}
</style>
