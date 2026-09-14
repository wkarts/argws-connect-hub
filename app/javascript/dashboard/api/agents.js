/* global axios */

import ApiClient from './ApiClient';

class Agents extends ApiClient {
  constructor() {
    super('agents', { accountScoped: true });
  }

  bulkInvite({ emails }) {
    return axios.post(`${this.url}/bulk_create`, {
      emails,
    });
  }

  resetTwoFactor(id) {
    return axios.patch(`${this.url}/${id}`, {
      reset_two_factor: true,
    });
  }
}

export default new Agents();
