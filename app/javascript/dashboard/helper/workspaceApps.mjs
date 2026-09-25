export const workspaceScope = (accountId, userId) => {
  const account = Number(accountId);
  const user = Number(userId);
  return Number.isSafeInteger(account) && account > 0 && Number.isSafeInteger(user) && user > 0 ? `${account}:${user}` : '';
};

export const safeApplicationUrl = (value, hubOrigin) => {
  try {
    if (typeof value !== 'string' || value.length > 2048 || /[\s\\\x00-\x1f]/.test(value)) return false;
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && url.origin !== hubOrigin;
  } catch (_) {
    return false;
  }
};

export const reconcileWorkspaceTabs = (tabs, apps) => {
  const available = new Map(apps.map(app => [Number(app.id), app]));
  return tabs.flatMap(tab => {
    const app = available.get(Number(tab.id));
    if (!app || !app.enabled || app.launch_mode !== 'embedded' || app.integration_revision !== tab.app.integration_revision) return [];
    // A name/icon change updates the header, not the iframe identity or URL.
    return [{ ...tab, app }];
  });
};

export const validateLoginPayload = (app, payload, hubOrigin) => {
  if (!safeApplicationUrl(app.url, hubOrigin) || !safeApplicationUrl(payload.action, hubOrigin)) return false;
  return app.auth_mode === 'form_post' && payload.action === app.login_url &&
    new URL(payload.action).origin === new URL(app.url).origin &&
    payload.integration_revision === app.integration_revision &&
    payload.username_field === app.username_field && payload.password_field === app.password_field &&
    typeof payload.username === 'string' && typeof payload.password === 'string';
};

// No axios here: its HUB authentication headers must never reach another origin.
export const submitApplicationLogin = (document, frame, app, payload, hubOrigin) => {
  if (!frame?.isConnected || !frame.name || !validateLoginPayload(app, payload, hubOrigin)) {
    throw new Error('application_configuration_changed');
  }
  const form = document.createElement('form');
  form.method = 'POST';
  form.action = payload.action;
  form.target = frame.name;
  form.hidden = true;
  form.autocomplete = 'off';
  for (const [name, value] of [[payload.username_field, payload.username], [payload.password_field, payload.password]]) {
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = name;
    input.value = value;
    form.appendChild(input);
  }
  document.body.appendChild(form);
  try {
    document.defaultView.HTMLFormElement.prototype.submit.call(form);
  } finally {
    Array.from(form.elements).forEach(input => { input.value = ''; });
    form.remove();
    payload.password = '';
    payload.username = '';
  }
};
