<script>
import { useAlert } from 'dashboard/composables';
import TwoFactorAuthenticationAPI from 'dashboard/api/twoFactorAuthentication';

export default {
  data() {
    return {
      loading: true,
      submitting: false,
      status: {
        enabled: false,
        enabled_at: null,
        setup_pending: false,
        recovery_codes_remaining: 0,
      },
      currentPassword: '',
      code: '',
      recoveryCode: '',
      useRecoveryCode: false,
      setup: null,
      recoveryCodes: [],
    };
  },
  mounted() {
    this.loadStatus();
  },
  methods: {
    async loadStatus() {
      this.loading = true;
      try {
        const { data } = await TwoFactorAuthenticationAPI.getStatus();
        this.status = data;
      } catch (error) {
        useAlert(this.errorMessage(error, 'Não foi possível consultar o 2FA.'));
      } finally {
        this.loading = false;
      }
    },
    errorMessage(error, fallback) {
      return error?.response?.data?.error || fallback;
    },
    async startSetup() {
      if (!this.currentPassword) {
        useAlert('Informe sua senha atual para ativar o 2FA.');
        return;
      }

      this.submitting = true;
      try {
        const { data } = await TwoFactorAuthenticationAPI.setup(
          this.currentPassword
        );
        this.setup = {
          secret: data.secret,
          provisioningUri: data.provisioning_uri,
        };
        this.status = data;
        this.code = '';
        useAlert('Chave 2FA gerada. Adicione-a ao seu aplicativo autenticador.');
      } catch (error) {
        useAlert(this.errorMessage(error, 'Não foi possível iniciar o 2FA.'));
      } finally {
        this.submitting = false;
      }
    },
    async confirmSetup() {
      if (!/^\d{6}$/.test(this.code)) {
        useAlert('Digite o código de 6 dígitos do aplicativo autenticador.');
        return;
      }

      this.submitting = true;
      try {
        const { data } = await TwoFactorAuthenticationAPI.confirm(this.code);
        this.status = data;
        this.recoveryCodes = data.recovery_codes || [];
        this.setup = null;
        this.currentPassword = '';
        this.code = '';
        useAlert('Autenticação em duas etapas ativada.');
      } catch (error) {
        useAlert(this.errorMessage(error, 'Código de autenticação inválido.'));
      } finally {
        this.submitting = false;
      }
    },
    secondFactorPayload() {
      return {
        currentPassword: this.currentPassword,
        code: this.useRecoveryCode ? '' : this.code,
        recoveryCode: this.useRecoveryCode ? this.recoveryCode : '',
      };
    },
    validateProtectedAction() {
      if (!this.currentPassword) {
        useAlert('Informe sua senha atual.');
        return false;
      }
      if (!this.code && !this.recoveryCode) {
        useAlert('Informe o código do autenticador ou um código de recuperação.');
        return false;
      }
      return true;
    },
    async regenerateRecoveryCodes() {
      if (!this.validateProtectedAction()) return;

      this.submitting = true;
      try {
        const { data } =
          await TwoFactorAuthenticationAPI.regenerateRecoveryCodes(
            this.secondFactorPayload()
          );
        this.status = data;
        this.recoveryCodes = data.recovery_codes || [];
        this.resetProtectedFields();
        useAlert(
          'Novos códigos de recuperação gerados. Os anteriores foram invalidados.'
        );
      } catch (error) {
        useAlert(
          this.errorMessage(
            error,
            'Não foi possível gerar novos códigos de recuperação.'
          )
        );
      } finally {
        this.submitting = false;
      }
    },
    async disableTwoFactor() {
      if (!this.validateProtectedAction()) return;

      this.submitting = true;
      try {
        const { data } = await TwoFactorAuthenticationAPI.disable(
          this.secondFactorPayload()
        );
        this.status = data;
        this.setup = null;
        this.recoveryCodes = [];
        this.resetProtectedFields();
        useAlert('Autenticação em duas etapas desativada.');
      } catch (error) {
        useAlert(this.errorMessage(error, 'Não foi possível desativar o 2FA.'));
      } finally {
        this.submitting = false;
      }
    },
    resetProtectedFields() {
      this.currentPassword = '';
      this.code = '';
      this.recoveryCode = '';
      this.useRecoveryCode = false;
    },
    async copyText(value, message) {
      try {
        await navigator.clipboard.writeText(value);
        useAlert(message);
      } catch (error) {
        useAlert('Não foi possível copiar automaticamente.');
      }
    },
    async copyRecoveryCodes() {
      await this.copyText(
        this.recoveryCodes.join('\n'),
        'Códigos de recuperação copiados.'
      );
    },
  },
};
</script>

<template>
  <div class="w-full space-y-5">
    <div v-if="loading" class="text-sm text-slate-500">
      Consultando autenticação em duas etapas...
    </div>

    <template v-else>
      <div class="flex items-center justify-between gap-4">
        <div>
          <p class="font-medium text-slate-900 dark:text-slate-100">
            {{ status.enabled ? '2FA ativado' : '2FA desativado' }}
          </p>
          <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
            Google Authenticator, Microsoft Authenticator e aplicativos compatíveis com TOTP.
          </p>
        </div>
        <span
          class="px-3 py-1 text-xs font-medium rounded-full"
          :class="
            status.enabled
              ? 'bg-green-100 text-green-800'
              : 'bg-slate-100 text-slate-700'
          "
        >
          {{ status.enabled ? 'Ativo' : 'Inativo' }}
        </span>
      </div>

      <div v-if="!status.enabled" class="space-y-4">
        <label class="block">
          <span class="text-sm font-medium text-slate-700 dark:text-slate-200">
            Senha atual
          </span>
          <input
            v-model="currentPassword"
            type="password"
            autocomplete="current-password"
            class="block w-full mt-1 rounded-md border-slate-300 dark:bg-slate-800 dark:border-slate-600"
          />
        </label>
        <button
          v-if="!setup"
          type="button"
          class="button nice primary"
          :disabled="submitting"
          @click="startSetup"
        >
          Ativar autenticação em duas etapas
        </button>

        <div
          v-if="setup"
          class="p-4 space-y-4 border rounded-lg border-slate-200 dark:border-slate-700"
        >
          <div>
            <p class="text-sm font-medium text-slate-900 dark:text-slate-100">
              1. Adicione a conta no aplicativo autenticador
            </p>
            <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
              Use a chave abaixo no Google Authenticator, Microsoft Authenticator ou outro app TOTP.
            </p>
          </div>
          <div class="flex items-center gap-2">
            <code
              class="flex-1 p-3 text-sm break-all rounded bg-slate-100 dark:bg-slate-900"
            >{{ setup.secret }}</code>
            <button
              type="button"
              class="button nice secondary"
              @click="copyText(setup.secret, 'Chave 2FA copiada.')"
            >
              Copiar
            </button>
          </div>
          <a :href="setup.provisioningUri" class="text-sm text-link">
            Abrir no aplicativo autenticador
          </a>
          <label class="block">
            <span class="text-sm font-medium text-slate-700 dark:text-slate-200">
              2. Código de 6 dígitos
            </span>
            <input
              v-model="code"
              type="text"
              inputmode="numeric"
              autocomplete="one-time-code"
              maxlength="6"
              class="block w-full mt-1 rounded-md border-slate-300 dark:bg-slate-800 dark:border-slate-600"
            />
          </label>
          <button
            type="button"
            class="button nice primary"
            :disabled="submitting"
            @click="confirmSetup"
          >
            Confirmar e ativar 2FA
          </button>
        </div>
      </div>

      <div v-else class="space-y-4">
        <p class="text-sm text-slate-600 dark:text-slate-400">
          Códigos de recuperação restantes:
          <strong>{{ status.recovery_codes_remaining }}</strong>
        </p>
        <label class="block">
          <span class="text-sm font-medium text-slate-700 dark:text-slate-200">
            Senha atual
          </span>
          <input
            v-model="currentPassword"
            type="password"
            autocomplete="current-password"
            class="block w-full mt-1 rounded-md border-slate-300 dark:bg-slate-800 dark:border-slate-600"
          />
        </label>
        <label class="block">
          <span class="text-sm font-medium text-slate-700 dark:text-slate-200">
            {{
              useRecoveryCode ? 'Código de recuperação' : 'Código do autenticador'
            }}
          </span>
          <input
            v-if="!useRecoveryCode"
            v-model="code"
            type="text"
            inputmode="numeric"
            autocomplete="one-time-code"
            maxlength="6"
            class="block w-full mt-1 rounded-md border-slate-300 dark:bg-slate-800 dark:border-slate-600"
          />
          <input
            v-else
            v-model="recoveryCode"
            type="text"
            autocomplete="off"
            class="block w-full mt-1 rounded-md border-slate-300 dark:bg-slate-800 dark:border-slate-600"
          />
        </label>
        <button
          type="button"
          class="text-sm text-link"
          @click="useRecoveryCode = !useRecoveryCode"
        >
          {{
            useRecoveryCode
              ? 'Usar aplicativo autenticador'
              : 'Usar código de recuperação'
          }}
        </button>
        <div class="flex flex-wrap gap-3">
          <button
            type="button"
            class="button nice secondary"
            :disabled="submitting"
            @click="regenerateRecoveryCodes"
          >
            Gerar novos códigos de recuperação
          </button>
          <button
            type="button"
            class="button nice alert"
            :disabled="submitting"
            @click="disableTwoFactor"
          >
            Desativar 2FA
          </button>
        </div>
      </div>

      <div
        v-if="recoveryCodes.length"
        class="p-4 space-y-3 border rounded-lg border-amber-300 bg-amber-50 dark:bg-slate-900"
      >
        <div>
          <p class="font-medium text-slate-900 dark:text-slate-100">
            Guarde seus códigos de recuperação
          </p>
          <p class="mt-1 text-sm text-slate-600 dark:text-slate-400">
            Eles são exibidos apenas agora. Cada código funciona uma única vez.
          </p>
        </div>
        <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <code
            v-for="item in recoveryCodes"
            :key="item"
            class="p-2 text-sm rounded bg-white dark:bg-slate-800"
          >{{ item }}</code>
        </div>
        <button
          type="button"
          class="button nice secondary"
          @click="copyRecoveryCodes"
        >
          Copiar todos
        </button>
      </div>
    </template>
  </div>
</template>
