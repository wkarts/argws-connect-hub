import Cookies from 'js-cookie';
import { IFrameHelper } from '../sdk/IFrameHelper';
import {
  getBubbleView,
  getDarkMode,
  getWidgetStyle,
} from '../sdk/settingsHelper';
import {
  computeHashForUserData,
  getUserCookieName,
  hasUserKeys,
} from '../sdk/cookieHelpers';
import {
  addClasses,
  removeClasses,
  restoreWidgetInDOM,
} from '../sdk/DOMHelpers';
import { setCookieWithDomain } from '../sdk/cookieHelpers';
import { SDK_SET_BUBBLE_VISIBILITY } from 'shared/constants/sharedFrameEvents';

const runSDK = ({ baseUrl, websiteToken }) => {
  if (window.$hub) {
    return;
  }

  if (window.Turbo) {
    // if this is a Rails Turbo app
    document.addEventListener('turbo:before-render', event =>
      restoreWidgetInDOM(event.detail.newBody)
    );
  }

  if (window.Turbolinks) {
    document.addEventListener('turbolinks:before-render', event => {
      restoreWidgetInDOM(event.data.newBody);
    });
  }

  // if this is an astro app
  document.addEventListener('astro:before-swap', event =>
    restoreWidgetInDOM(event.newDocument.body)
  );

  const hubSettings = window.hubSettings || {};
  let locale = hubSettings.locale;
  let baseDomain = hubSettings.baseDomain;

  if (hubSettings.useBrowserLanguage) {
    locale = window.navigator.language.replace('-', '_');
  }

  window.$hub = {
    baseUrl,
    baseDomain,
    hasLoaded: false,
    hideMessageBubble: hubSettings.hideMessageBubble || false,
    isOpen: false,
    position: hubSettings.position === 'left' ? 'left' : 'right',
    websiteToken,
    locale,
    useBrowserLanguage: hubSettings.useBrowserLanguage || false,
    type: getBubbleView(hubSettings.type),
    launcherTitle: hubSettings.launcherTitle || '',
    showPopoutButton: hubSettings.showPopoutButton || false,
    showUnreadMessagesDialog: hubSettings.showUnreadMessagesDialog ?? true,
    widgetStyle: getWidgetStyle(hubSettings.widgetStyle) || 'standard',
    resetTriggered: false,
    darkMode: getDarkMode(hubSettings.darkMode),

    toggle(state) {
      IFrameHelper.events.toggleBubble(state);
    },

    toggleBubbleVisibility(visibility) {
      let widgetElm = document.querySelector('.hub--bubble-holder');
      let widgetHolder = document.querySelector('.hub-widget-holder');
      if (visibility === 'hide') {
        addClasses(widgetHolder, 'hub-widget--without-bubble');
        addClasses(widgetElm, 'hub-hidden');
        window.$hub.hideMessageBubble = true;
      } else if (visibility === 'show') {
        removeClasses(widgetElm, 'hub-hidden');
        removeClasses(widgetHolder, 'hub-widget--without-bubble');
        window.$hub.hideMessageBubble = false;
      }
      IFrameHelper.sendMessage(SDK_SET_BUBBLE_VISIBILITY, {
        hideMessageBubble: window.$hub.hideMessageBubble,
      });
    },

    popoutChatWindow() {
      IFrameHelper.events.popoutChatWindow({
        baseUrl: window.$hub.baseUrl,
        websiteToken: window.$hub.websiteToken,
        locale,
      });
    },

    setUser(identifier, user) {
      if (typeof identifier !== 'string' && typeof identifier !== 'number') {
        throw new Error('Identifier should be a string or a number');
      }

      if (!hasUserKeys(user)) {
        throw new Error(
          'User object should have one of the keys [avatar_url, email, name]'
        );
      }

      const userCookieName = getUserCookieName();
      const existingCookieValue = Cookies.get(userCookieName);
      const hashToBeStored = computeHashForUserData({ identifier, user });
      if (hashToBeStored === existingCookieValue) {
        return;
      }

      window.$hub.identifier = identifier;
      window.$hub.user = user;
      IFrameHelper.sendMessage('set-user', { identifier, user });

      setCookieWithDomain(userCookieName, hashToBeStored, {
        baseDomain,
      });
    },

    setCustomAttributes(customAttributes = {}) {
      if (!customAttributes || !Object.keys(customAttributes).length) {
        throw new Error('Custom attributes should have atleast one key');
      } else {
        IFrameHelper.sendMessage('set-custom-attributes', { customAttributes });
      }
    },

    deleteCustomAttribute(customAttribute = '') {
      if (!customAttribute) {
        throw new Error('Custom attribute is required');
      } else {
        IFrameHelper.sendMessage('delete-custom-attribute', {
          customAttribute,
        });
      }
    },

    setConversationCustomAttributes(customAttributes = {}) {
      if (!customAttributes || !Object.keys(customAttributes).length) {
        throw new Error('Custom attributes should have atleast one key');
      } else {
        IFrameHelper.sendMessage('set-conversation-custom-attributes', {
          customAttributes,
        });
      }
    },

    deleteConversationCustomAttribute(customAttribute = '') {
      if (!customAttribute) {
        throw new Error('Custom attribute is required');
      } else {
        IFrameHelper.sendMessage('delete-conversation-custom-attribute', {
          customAttribute,
        });
      }
    },

    setLabel(label = '') {
      IFrameHelper.sendMessage('set-label', { label });
    },

    removeLabel(label = '') {
      IFrameHelper.sendMessage('remove-label', { label });
    },

    setLocale(localeToBeUsed = 'en') {
      IFrameHelper.sendMessage('set-locale', { locale: localeToBeUsed });
    },

    setColorScheme(darkMode = 'light') {
      IFrameHelper.sendMessage('set-color-scheme', {
        darkMode: getDarkMode(darkMode),
      });
    },

    reset() {
      if (window.$hub.isOpen) {
        IFrameHelper.events.toggleBubble();
      }

      Cookies.remove('hub_conversation');
      Cookies.remove(getUserCookieName());

      const iframe = IFrameHelper.getAppFrame();
      iframe.src = IFrameHelper.getUrl({
        baseUrl: window.$hub.baseUrl,
        websiteToken: window.$hub.websiteToken,
      });

      window.$hub.resetTriggered = true;
    },
  };

  IFrameHelper.createFrame({
    baseUrl,
    websiteToken,
  });
};

window.hubSDK = {
  run: runSDK,
};
