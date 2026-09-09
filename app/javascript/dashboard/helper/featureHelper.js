const FEATURE_HELP_URLS = {
  agent_bots: '/help/?feature=agent-bots',
  agents: '/help/?feature=agents',
  audit_logs: '/help/?feature=audit-logs',
  campaigns: '/help/?feature=campaigns',
  canned_responses: '/help/?feature=canned-responses',
  channel_email: '/help/?feature=channel-email',
  channel_facebook: '/help/?feature=channel-facebook',
  custom_attributes: '/help/?feature=custom-attributes',
  dashboard_apps: '/help/?feature=dashboard-apps',
  help_center: '/help/?feature=help-center',
  inboxes: '/help/?feature=inboxes',
  integrations: '/help/?feature=integrations',
  labels: '/help/?feature=labels',
  macros: '/help/?feature=macros',
  message_reply_to: '/help/?feature=message-reply-to',
  reports: '/help/?feature=reports',
  sla: '/help/?feature=sla',
  captain: '/help/?feature=captain',
  team_management: '/help/?feature=team-management',
  webhook: '/help/?feature=webhooks',
};

export function getHelpUrlForFeature(featureName) {
  return FEATURE_HELP_URLS[featureName] || '/help/';
}
