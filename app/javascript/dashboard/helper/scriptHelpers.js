import DashboardAudioNotificationHelper from './AudioAlerts/DashboardAudioNotificationHelper';
import { emitter } from 'shared/helpers/mitt';

export const HUB_SET_USER = 'HUB_SET_USER';
export const HUB_RESET = 'HUB_RESET';


const initializeAudioAlerts = user => {
  const { ui_settings: uiSettings } = user || {};
  const {
    always_play_audio_alert: alwaysPlayAudioAlert,
    enable_audio_alerts: audioAlertType,
    alert_if_unread_assigned_conversation_exist: alertIfUnreadConversationExist,
    notification_tone: audioAlertTone,
    // UI Settings can be undefined initally as we don't send the
    // entire payload for the user during the signup process.
  } = uiSettings || {};

  DashboardAudioNotificationHelper.setInstanceValues({
    currentUserId: user.id,
    audioAlertType: audioAlertType || 'none',
    audioAlertTone: audioAlertTone || 'ding',
    alwaysPlayAudioAlert: alwaysPlayAudioAlert || false,
    alertIfUnreadConversationExist: alertIfUnreadConversationExist || false,
  });
};

export const initializeHubEvents = () => {
  emitter.on(HUB_SET_USER, ({ user }) => {
    initializeAudioAlerts(user);
  });
};
