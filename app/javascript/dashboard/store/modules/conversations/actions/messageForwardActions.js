import MessageApi from '../../../../api/inbox/message';

export default {
  async forwardMessage(_, { conversationId, messageId, contacts }) {
    const response = await MessageApi.forwardMessage(
      conversationId,
      messageId,
      contacts
    );
    return response.data;
  },
};
