export const GROUP_EVENT = 'whatsapp_group.changed';
export const groupFailure = (error, fallback) => {
  const value = error?.response?.data?.error || error?.response?.data?.message;
  return typeof value === 'string' && !/<[a-z!]/i.test(value) ? value.slice(0, 500) : fallback;
};
export const groupDestination = (accountId, group, history = false) => {
  const params = { accountId, inbox_id: group.inbox_id };
  if (group.treatment === 'conversation' && group.conversation_id && !history) {
    return { name: 'conversation_through_inbox', params: { ...params, conversation_id: group.conversation_id }, query: { groupTab: '1' } };
  }
  return { name: 'inbox_dashboard', params, query: { groupId: String(group.id), groupTab: '1', ...(history ? { groupHistory: '1' } : {}) } };
};
export const mergeGroupMessages = (current, incoming) => {
  const values = new Map(current.map(message => [message.id, message]));
  incoming.forEach(message => values.set(message.id, message));
  return [...values.values()].sort((a, b) => a.id - b.id);
};
