const FEATURE_HELP_URLS = {
  agent_bots: '/docs/?feature=agent-bots',
  agents: '/docs/?feature=agents',
  audit_logs: '/docs/?feature=audit-logs',
  campaigns: '/docs/?feature=campaigns',
  canned_responses: '/docs/?feature=canned-responses',
  channel_email: '/docs/?feature=channel-email',
  channel_facebook: '/docs/?feature=channel-facebook',
  custom_attributes: '/docs/?feature=custom-attributes',
  dashboard_apps: '/docs/?feature=dashboard-apps',
  help_center: '/docs/?feature=help-center',
  inboxes: '/docs/?feature=inboxes',
  integrations: '/docs/?feature=integrations',
  labels: '/docs/?feature=labels',
  macros: '/docs/?feature=macros',
  message_reply_to: '/docs/?feature=message-reply-to',
  reports: '/docs/?feature=reports',
  sla: '/docs/?feature=sla',
  captain: '/docs/?feature=captain',
  team_management: '/docs/?feature=team-management',
  webhook: '/docs/?feature=webhooks',
};

export function getHelpUrlForFeature(featureName) {
  return FEATURE_HELP_URLS[featureName] || '/docs/';
}
