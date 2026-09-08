<template>
  <form class="mx-0 flex flex-wrap" @submit.prevent="createChannel">
    <div class="w-[65%] max-w-[65%]">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input v-model.trim="inboxName" type="text" @blur="v$.inboxName.$touch" />
      </label>
    </div>
    <div class="w-[65%] max-w-[65%]">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input v-model.trim="phoneNumber" type="text" placeholder="+5575999999999" @blur="v$.phoneNumber.$touch" />
      </label>
    </div>
    <div class="w-[65%] max-w-[65%]">
      <label>Forma de conexão</label>
      <select v-model="authMode">
        <option value="qrcode">QR Code</option>
        <option value="pairing_code">Código de pareamento</option>
      </select>
      <p class="text-xs text-slate-500 mt-1">A credencial administrativa da Connect|API permanece somente no servidor do HUB.</p>
    </div>
    <div class="w-full mt-5">
      <hub-submit-button :loading="uiFlags.isCreating" button-text="Criar caixa e conectar" />
    </div>
  </form>
</template>

<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import router from '../../../../index';
import { isPhoneE164OrEmpty } from 'shared/helpers/Validators';

export default {
  setup() { return { v$: useVuelidate() }; },
  data() { return { inboxName: '', phoneNumber: '', authMode: 'qrcode' }; },
  computed: { ...mapGetters({ uiFlags: 'inboxes/getUIFlags' }) },
  validations: { inboxName: { required }, phoneNumber: { required, isPhoneE164OrEmpty } },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) return;
      try {
        const channel = await this.$store.dispatch('inboxes/createChannel', {
          name: this.inboxName,
          channel: {
            type: 'whatsapp',
            phone_number: this.phoneNumber,
            provider: 'connectapi',
            provider_config: {
              auth_mode: this.authMode,
              connect: true,
              ignore_group_messages: true,
              ignore_history_messages: true,
              send_agent_name: true
            }
          }
        });
        router.replace({ name: 'settings_inboxes_add_agents', params: { page: 'new', inbox_id: channel.id } });
      } catch (error) {
        useAlert(error?.message || 'Não foi possível provisionar a Connect|API.');
      }
    }
  }
};
</script>
