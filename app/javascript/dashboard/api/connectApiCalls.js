/* global axios */
import ApiClient from './ApiClient';

class ConnectApiCallsAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  callUrl(conversationId, suffix = '') {
    const base = `${this.url}/${conversationId}/connect_api_calls`;
    return suffix ? `${base}/${suffix}` : base;
  }

  status(conversationId) {
    return axios.get(this.callUrl(conversationId));
  }

  offer(conversationId) {
    return axios.post(this.callUrl(conversationId), { is_video: false });
  }

  action(conversationId, action, payload) {
    return axios.post(this.callUrl(conversationId, action), payload);
  }

  mediaTicket(conversationId, callId) {
    return axios.post(this.callUrl(conversationId, 'media_ticket'), {
      call_id: callId,
    });
  }
}

export default new ConnectApiCallsAPI();
