/* global axios */
import ApiClient from './ApiClient';

class LinkPreviewAPI extends ApiClient {
  constructor() {
    super('link_preview', { accountScoped: true });
  }

  get(url) {
    return axios.get(this.url, {
      params: { url },
    });
  }
}

export default new LinkPreviewAPI();
