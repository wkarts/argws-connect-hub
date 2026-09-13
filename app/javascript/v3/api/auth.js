import {
  setAuthCredentials,
  throwErrorMessage,
  clearLocalStorageOnLogout,
} from 'dashboard/store/utils/api';
import { frontendURL } from 'dashboard/helper/URLHelper';
import hubAPI from './apiClient';
import { getLoginRedirectURL } from '../helpers/AuthHelper';

const TWO_FACTOR_CHALLENGE_KEY = 'hub_two_factor_challenge';
const TWO_FACTOR_CONTEXT_KEY = 'hub_two_factor_context';

const completeLogin = ({ response, ssoAccountId, ssoConversationId }) => {
  setAuthCredentials(response);
  clearLocalStorageOnLogout();
  sessionStorage.removeItem(TWO_FACTOR_CHALLENGE_KEY);
  sessionStorage.removeItem(TWO_FACTOR_CONTEXT_KEY);
  window.location = getLoginRedirectURL({
    ssoAccountId,
    ssoConversationId,
    user: response.data.data,
  });
};

export const login = async ({
  ssoAccountId,
  ssoConversationId,
  ...credentials
}) => {
  try {
    const response = await hubAPI.post('frontend_auth/sign_in', credentials);

    if (response.data?.two_factor_required) {
      sessionStorage.setItem(TWO_FACTOR_CHALLENGE_KEY, response.data.challenge);
      sessionStorage.setItem(
        TWO_FACTOR_CONTEXT_KEY,
        JSON.stringify({ ssoAccountId, ssoConversationId })
      );
      window.location = frontendURL('login/two-factor');
      return;
    }

    completeLogin({ response, ssoAccountId, ssoConversationId });
  } catch (error) {
    throwErrorMessage(error);
  }
};

export const getTwoFactorLoginContext = () => {
  const challenge = sessionStorage.getItem(TWO_FACTOR_CHALLENGE_KEY);
  let context = {};

  try {
    context = JSON.parse(sessionStorage.getItem(TWO_FACTOR_CONTEXT_KEY) || '{}');
  } catch (error) {
    context = {};
  }

  return { challenge, ...context };
};

export const clearTwoFactorLoginContext = () => {
  sessionStorage.removeItem(TWO_FACTOR_CHALLENGE_KEY);
  sessionStorage.removeItem(TWO_FACTOR_CONTEXT_KEY);
};

export const verifyTwoFactor = async ({
  challenge,
  code,
  recoveryCode,
  ssoAccountId,
  ssoConversationId,
}) => {
  try {
    const response = await hubAPI.post('frontend_auth/two_factor/verify', {
      challenge,
      code,
      recovery_code: recoveryCode,
    });
    completeLogin({ response, ssoAccountId, ssoConversationId });
  } catch (error) {
    throwErrorMessage(error);
  }
};

export const register = async creds => {
  try {
    const response = await hubAPI.post('api/v1/accounts.json', {
      account_name: creds.accountName.trim(),
      user_full_name: creds.fullName.trim(),
      email: creds.email,
      password: creds.password,
      h_captcha_client_response: creds.hCaptchaClientResponse,
    });
    setAuthCredentials(response);
    return response.data;
  } catch (error) {
    throwErrorMessage(error);
  }
  return null;
};

export const verifyPasswordToken = async ({ confirmationToken }) => {
  try {
    const response = await hubAPI.post('auth/confirmation', {
      confirmation_token: confirmationToken,
    });
    setAuthCredentials(response);
  } catch (error) {
    throwErrorMessage(error);
  }
};

export const setNewPassword = async ({
  resetPasswordToken,
  password,
  confirmPassword,
}) => {
  try {
    const response = await hubAPI.put('auth/password', {
      reset_password_token: resetPasswordToken,
      password_confirmation: confirmPassword,
      password,
    });
    setAuthCredentials(response);
  } catch (error) {
    throwErrorMessage(error);
  }
};

export const resetPassword = async ({ email }) =>
  hubAPI.post('auth/password', { email });
