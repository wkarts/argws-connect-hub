/* global axios */
// Bind every request to the account that initiated it, including late responses.
const root = account => `/api/v1/accounts/${Number(account)}`;
const groups = account => `${root(account)}/whatsapp_groups`;
const settings = (account, inbox) => `${root(account)}/inboxes/${Number(inbox)}/whatsapp_group_settings`;
export default {
  settings: (account, inbox, params = {}) => axios.get(settings(account, inbox), { params }),
  saveSettings: (account, inbox, data) => axios.patch(settings(account, inbox), data),
  sync: (account, inbox) => axios.post(`${settings(account, inbox)}/sync`),
  saveGroup: (account, inbox, id, data) => axios.patch(`${settings(account, inbox)}/groups/${Number(id)}`, data),
  bulk: (account, inbox, data) => axios.patch(`${settings(account, inbox)}/bulk_update`, data),
  replay: (account, inbox, id) => axios.post(`${settings(account, inbox)}/groups/${Number(id)}/replay`, { confirmed: true }),
  list: (account, params = {}) => axios.get(groups(account), { params }),
  show: (account, id) => axios.get(`${groups(account)}/${Number(id)}`),
  messages: (account, id, params = {}, legacy = false) => axios.get(`${groups(account)}/${Number(id)}/${legacy ? 'legacy_messages' : 'messages'}`, { params }),
  message: (account, id, message) => axios.get(`${groups(account)}/${Number(id)}/messages/${Number(message)}`),
  send: (account, id, data) => axios.post(`${groups(account)}/${Number(id)}/messages`, data),
  revoke: (account, id, message) => axios.delete(`${groups(account)}/${Number(id)}/messages/${Number(message)}`),
  cancel: (account, id, message) => axios.post(`${groups(account)}/${Number(id)}/messages/${Number(message)}/cancel`, { confirmed: true }),
  preference: (account, id, preference) => axios.patch(`${groups(account)}/${Number(id)}/preference`, { preference }),
};
