<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import globalConfigMixin from 'shared/mixins/globalConfigMixin';
import FormInput from '../../components/Form/Input.vue';
import SubmitButton from '../../components/Button/SubmitButton.vue';
import {
  clearTwoFactorLoginContext,
  getTwoFactorLoginContext,
  verifyTwoFactor,
} from '../../api/auth';

export default {
  components: { FormInput, SubmitButton },
  mixins: [globalConfigMixin],
  data() {
    return {
      challenge: '',
      ssoAccountId: '',
      ssoConversationId: '',
      code: '',
      recoveryCode: '',
      useRecoveryCode: false,
      loading: false,
      hasErrored: false,
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    inputValue: {
      get() {
        return this.useRecoveryCode ? this.recoveryCode : this.code;
      },
      set(value) {
        if (this.useRecoveryCode) this.recoveryCode = value;
        else this.code = value.replace(/\D/g, '').slice(0, 6);
      },
    },
  },
  created() {
    const context = getTwoFactorLoginContext();
    if (!context.challenge) {
      window.location = frontendURL('login');
      return;
    }

    this.challenge = context.challenge;
    this.ssoAccountId = context.ssoAccountId || '';
    this.ssoConversationId = context.ssoConversationId || '';
  },
  methods: {
    async submit() {
      if (!this.inputValue) return;

      this.loading = true;
      this.hasErrored = false;
      try {
        await verifyTwoFactor({
          challenge: this.challenge,
          code: this.useRecoveryCode ? '' : this.code,
          recoveryCode: this.useRecoveryCode ? this.recoveryCode : '',
          ssoAccountId: this.ssoAccountId,
          ssoConversationId: this.ssoConversationId,
        });
      } catch (error) {
        this.hasErrored = true;
        this.loading = false;
        useAlert(error?.message || 'Código de autenticação inválido.');
      }
    },
    toggleRecoveryCode() {
      this.useRecoveryCode = !this.useRecoveryCode;
      this.code = '';
      this.recoveryCode = '';
    },
    backToLogin() {
      clearTwoFactorLoginContext();
      window.location = frontendURL('login');
    },
  },
};
</script>

<template>
  <main
    class="flex flex-col w-full min-h-screen py-20 bg-hub-25 sm:px-6 lg:px-8 dark:bg-slate-900"
  >
    <section class="max-w-5xl mx-auto">
      <img
        :src="globalConfig.logo"
        :alt="globalConfig.installationName"
        class="block w-auto h-8 mx-auto dark:hidden"
      />
      <img
        v-if="globalConfig.logoDark"
        :src="globalConfig.logoDark"
        :alt="globalConfig.installationName"
        class="hidden w-auto h-8 mx-auto dark:block"
      />
      <h2 class="mt-6 text-3xl font-medium text-center text-slate-900 dark:text-hub-50">
        Verificação em duas etapas
      </h2>
      <p class="mt-3 text-sm text-center text-slate-600 dark:text-slate-400">
        {{
          useRecoveryCode
            ? 'Informe um dos seus códigos de recuperação.'
            : 'Digite o código de 6 dígitos do seu aplicativo autenticador.'
        }}
      </p>
    </section>

    <section
      class="bg-white shadow sm:mx-auto mt-11 sm:w-full sm:max-w-lg dark:bg-slate-800 p-11 sm:shadow-lg sm:rounded-lg"
      :class="{ 'animate-wiggle': hasErrored }"
    >
      <form class="space-y-5" @submit.prevent="submit">
        <FormInput
          v-model.trim="inputValue"
          type="text"
          name="two_factor_code"
          data-testid="two_factor_code_input"
          autocomplete="one-time-code"
          :label="useRecoveryCode ? 'Código de recuperação' : 'Código do autenticador'"
          :placeholder="useRecoveryCode ? 'XXXX-XXXX-XXXX-XXXX' : '000000'"
          required
        />

        <SubmitButton
          :disabled="loading"
          button-text="Verificar e entrar"
          :loading="loading"
        />

        <div class="flex items-center justify-between gap-4 text-sm">
          <button type="button" class="text-link" @click="toggleRecoveryCode">
            {{ useRecoveryCode ? 'Usar aplicativo autenticador' : 'Usar código de recuperação' }}
          </button>
          <button type="button" class="text-slate-600 dark:text-slate-300" @click="backToLogin">
            Voltar
          </button>
        </div>
      </form>
    </section>
  </main>
</template>
