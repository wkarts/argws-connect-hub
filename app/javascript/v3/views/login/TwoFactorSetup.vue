<script>
import qrcode from 'qrcode-generator';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import globalConfigMixin from 'shared/mixins/globalConfigMixin';
import FormInput from '../../components/Form/Input.vue';
import SubmitButton from '../../components/Button/SubmitButton.vue';
import {
  clearTwoFactorLoginContext,
  confirmTwoFactorEnrollment,
  finishTwoFactorEnrollment,
  getTwoFactorLoginContext,
  startTwoFactorEnrollment,
} from '../../api/auth';

export default {
  components: { FormInput, SubmitButton },
  mixins: [globalConfigMixin],
  data() {
    return {
      challenge: '',
      ssoAccountId: '',
      ssoConversationId: '',
      requiredByAccounts: [],
      secret: '',
      provisioningUri: '',
      code: '',
      recoveryCodes: [],
      authenticatedUser: null,
      loading: true,
      submitting: false,
      hasErrored: false,
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    qrCodeDataUrl() {
      if (!this.provisioningUri) return '';

      try {
        const qr = qrcode(0, 'M');
        qr.addData(this.provisioningUri);
        qr.make();
        return qr.createDataURL(6, 24);
      } catch (error) {
        return '';
      }
    },
    setupCompleted() {
      return this.recoveryCodes.length > 0 && !!this.authenticatedUser;
    },
    companyNames() {
      return this.requiredByAccounts.join(', ');
    },
  },
  created() {
    const context = getTwoFactorLoginContext();
    if (!context.challenge || !context.setupRequired) {
      window.location = frontendURL('login');
      return;
    }

    this.challenge = context.challenge;
    this.ssoAccountId = context.ssoAccountId || '';
    this.ssoConversationId = context.ssoConversationId || '';
    this.requiredByAccounts = context.requiredByAccounts || [];
    this.loadSetup();
  },
  methods: {
    async loadSetup() {
      this.loading = true;
      this.hasErrored = false;
      try {
        const response = await startTwoFactorEnrollment(this.challenge);
        if (!response) return;

        this.secret = response.data.secret;
        this.provisioningUri = response.data.provisioning_uri;
        this.requiredByAccounts =
          response.data.required_by_accounts || this.requiredByAccounts;
      } catch (error) {
        this.hasErrored = true;
        useAlert(error?.message || 'Não foi possível iniciar a configuração do 2FA.');
      } finally {
        this.loading = false;
      }
    },
    async submit() {
      if (!/^\d{6}$/.test(this.code)) {
        useAlert('Digite o código de 6 dígitos do aplicativo autenticador.');
        return;
      }

      this.submitting = true;
      this.hasErrored = false;
      try {
        const response = await confirmTwoFactorEnrollment({
          challenge: this.challenge,
          code: this.code,
        });
        if (!response) return;

        this.recoveryCodes = response.data.recovery_codes || [];
        this.authenticatedUser = response.data.data;
        this.code = '';
      } catch (error) {
        this.hasErrored = true;
        useAlert(error?.message || 'Código de autenticação inválido.');
      } finally {
        this.submitting = false;
      }
    },
    continueToHub() {
      finishTwoFactorEnrollment({
        user: this.authenticatedUser,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      });
    },
    async copyText(value, successMessage) {
      try {
        await navigator.clipboard.writeText(value);
        useAlert(successMessage);
      } catch (error) {
        useAlert('Não foi possível copiar automaticamente.');
      }
    },
    copyRecoveryCodes() {
      this.copyText(
        this.recoveryCodes.join('\n'),
        'Códigos de recuperação copiados.'
      );
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
    class="flex flex-col w-full min-h-screen py-12 bg-hub-25 sm:px-6 lg:px-8 dark:bg-slate-900"
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
        Configure a autenticação em duas etapas
      </h2>
      <p class="max-w-xl mt-3 text-sm text-center text-slate-600 dark:text-slate-400">
        Sua empresa exige 2FA para concluir o acesso ao HUB. Use Google Authenticator,
        Microsoft Authenticator ou qualquer aplicativo compatível com TOTP.
      </p>
      <p
        v-if="companyNames"
        class="max-w-xl mt-2 text-xs font-medium text-center text-slate-500 dark:text-slate-400"
      >
        Política aplicada por: {{ companyNames }}
      </p>
    </section>

    <section
      class="bg-white shadow sm:mx-auto mt-8 sm:w-full sm:max-w-xl dark:bg-slate-800 p-8 sm:shadow-lg sm:rounded-lg"
      :class="{ 'animate-wiggle': hasErrored }"
    >
      <div v-if="loading" class="py-12 text-sm text-center text-slate-500">
        Preparando configuração segura...
      </div>

      <template v-else-if="!setupCompleted">
        <div class="space-y-6">
          <div>
            <h3 class="text-base font-medium text-slate-900 dark:text-slate-100">
              1. Escaneie o QR Code
            </h3>
            <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
              No aplicativo autenticador, adicione uma nova conta e leia este código.
            </p>
          </div>

          <div
            v-if="qrCodeDataUrl"
            class="flex justify-center p-5 mx-auto bg-white border rounded-lg border-slate-200 w-fit"
          >
            <img
              :src="qrCodeDataUrl"
              alt="QR Code para configurar autenticação em duas etapas"
              class="w-56 h-56"
            />
          </div>

          <div class="p-4 border rounded-lg border-slate-200 dark:border-slate-700">
            <p class="text-sm font-medium text-slate-900 dark:text-slate-100">
              Não consegue escanear?
            </p>
            <p class="mt-1 text-xs text-slate-600 dark:text-slate-400">
              Digite esta chave manualmente no aplicativo autenticador.
            </p>
            <div class="flex items-center gap-2 mt-3">
              <code
                class="flex-1 p-3 text-sm break-all rounded bg-slate-100 dark:bg-slate-900"
              >{{ secret }}</code>
              <button
                type="button"
                class="button nice secondary"
                @click="copyText(secret, 'Chave 2FA copiada.')"
              >
                Copiar
              </button>
            </div>
          </div>

          <form class="space-y-5" @submit.prevent="submit">
            <div>
              <h3 class="mb-3 text-base font-medium text-slate-900 dark:text-slate-100">
                2. Confirme o código
              </h3>
              <FormInput
                v-model.trim="code"
                type="text"
                name="two_factor_setup_code"
                data-testid="two_factor_setup_code_input"
                autocomplete="one-time-code"
                label="Código de 6 dígitos"
                placeholder="000000"
                maxlength="6"
                required
              />
            </div>

            <SubmitButton
              :disabled="submitting"
              button-text="Ativar 2FA e concluir acesso"
              :loading="submitting"
            />

            <button
              type="button"
              class="w-full text-sm text-center text-slate-600 dark:text-slate-300"
              @click="backToLogin"
            >
              Voltar ao login
            </button>
          </form>
        </div>
      </template>

      <template v-else>
        <div class="space-y-5">
          <div>
            <h3 class="text-xl font-medium text-slate-900 dark:text-slate-100">
              2FA ativado com sucesso
            </h3>
            <p class="mt-2 text-sm text-slate-600 dark:text-slate-400">
              Guarde os códigos abaixo em um local seguro. Cada código funciona uma única vez
              caso você perca acesso ao aplicativo autenticador.
            </p>
          </div>

          <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <code
              v-for="item in recoveryCodes"
              :key="item"
              class="p-3 text-sm text-center rounded bg-slate-100 dark:bg-slate-900"
            >{{ item }}</code>
          </div>

          <button
            type="button"
            class="button nice secondary w-full"
            @click="copyRecoveryCodes"
          >
            Copiar códigos de recuperação
          </button>

          <button
            type="button"
            class="button nice primary w-full"
            @click="continueToHub"
          >
            Continuar para o HUB
          </button>
        </div>
      </template>
    </section>
  </main>
</template>
