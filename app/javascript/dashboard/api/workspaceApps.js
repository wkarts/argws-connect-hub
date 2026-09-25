/* global axios */
// The account is explicit: a late request must never inherit a newly selected company.
const base = accountId => `/api/v1/accounts/${Number(accountId)}/workspace_apps`;

export default {
  list: accountId => axios.get(base(accountId)),
  members: accountId => axios.get(`/api/v1/accounts/${Number(accountId)}/agents`),
  manage: accountId => axios.get(`${base(accountId)}/manage`),
  show: (accountId, id) => axios.get(`${base(accountId)}/${Number(id)}`),
  create: (accountId, data) => axios.post(base(accountId), data),
  update: (accountId, id, data) => axios.patch(`${base(accountId)}/${Number(id)}`, data),
  remove: (accountId, id) => axios.delete(`${base(accountId)}/${Number(id)}`),
  diagnose: (accountId, id) => axios.post(`${base(accountId)}/${Number(id)}/diagnose`),
  credential: (accountId, id) => axios.get(`${base(accountId)}/${Number(id)}/credential`),
  forgetCredential: (accountId, id) => axios.delete(`${base(accountId)}/${Number(id)}/credential`),
  launch: (accountId, id, data) => axios.post(`${base(accountId)}/${Number(id)}/launch`, data),
};
