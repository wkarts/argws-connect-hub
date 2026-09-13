/* global axios */

const endpoint = '/frontend_auth/two_factor/settings';

export default {
  getStatus() {
    return axios.get(endpoint);
  },

  setup(currentPassword) {
    return axios.post(endpoint, { current_password: currentPassword });
  },

  confirm(code) {
    return axios.post(`${endpoint}/confirm`, { code });
  },

  regenerateRecoveryCodes({ currentPassword, code, recoveryCode }) {
    return axios.post(`${endpoint}/recovery_codes`, {
      current_password: currentPassword,
      code,
      recovery_code: recoveryCode,
    });
  },

  disable({ currentPassword, code, recoveryCode }) {
    return axios.delete(endpoint, {
      data: {
        current_password: currentPassword,
        code,
        recovery_code: recoveryCode,
      },
    });
  },
};
