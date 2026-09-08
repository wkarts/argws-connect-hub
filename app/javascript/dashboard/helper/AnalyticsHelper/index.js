/**
 * HUB privacy-safe analytics shim.
 * No events, identities, page views or user data leave the installation.
 */
export class AnalyticsHelper {
  constructor() { this.user = {}; }
  async init() {}
  identify(user) { this.user = user || {}; }
  track() {}
  page() {}
}

export default new AnalyticsHelper();
