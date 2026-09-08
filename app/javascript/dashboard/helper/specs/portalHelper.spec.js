import { buildPortalArticleURL, buildPortalURL } from '../portalHelper';

describe('PortalHelper', () => {
  describe('buildPortalURL', () => {
    it('returns the correct url', () => {
      window.hubConfig = {
        hostURL: 'https://app.hub.com',
        helpCenterURL: 'https://help.hub.com',
      };
      expect(buildPortalURL('handbook')).toEqual(
        'https://help.hub.com/hc/handbook'
      );
      window.hubConfig = {};
    });
  });

  describe('buildPortalArticleURL', () => {
    it('returns the correct url', () => {
      window.hubConfig = {
        hostURL: 'https://app.hub.com',
        helpCenterURL: 'https://help.hub.com',
      };
      expect(
        buildPortalArticleURL('handbook', 'culture', 'fr', 'article-slug')
      ).toEqual('https://help.hub.com/hc/handbook/articles/article-slug');
      window.hubConfig = {};
    });
  });
});
