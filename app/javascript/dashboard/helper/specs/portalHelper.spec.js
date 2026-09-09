import { buildPortalArticleURL, buildPortalURL } from '../portalHelper';

describe('PortalHelper', () => {
  describe('buildPortalURL', () => {
    it('returns the correct url', () => {
      window.hubConfig = {
        hostURL: 'https://app.hub.invalid',
        helpCenterURL: 'https://help.hub.invalid',
      };
      expect(buildPortalURL('handbook')).toEqual(
        'https://help.hub.invalid/hc/handbook'
      );
      window.hubConfig = {};
    });
  });

  describe('buildPortalArticleURL', () => {
    it('returns the correct url', () => {
      window.hubConfig = {
        hostURL: 'https://app.hub.invalid',
        helpCenterURL: 'https://help.hub.invalid',
      };
      expect(
        buildPortalArticleURL('handbook', 'culture', 'fr', 'article-slug')
      ).toEqual('https://help.hub.invalid/hc/handbook/articles/article-slug');
      window.hubConfig = {};
    });
  });
});
