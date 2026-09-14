import ConversationHeader from '../ConversationHeader.vue';

describe('ConversationHeader call capabilities', () => {
  const buildCallInbox = inbox =>
    ConversationHeader.computed.callInbox.call({ inbox });

  it('uses public Connect API call capabilities when provider config is hidden', () => {
    const inbox = {
      id: 7,
      provider: 'connectapi',
      calls_supported: true,
      incoming_call_ring_enabled: false,
    };

    expect(buildCallInbox(inbox)).toEqual({
      ...inbox,
      provider_config: {
        calls_supported: true,
        incoming_call_ring_enabled: false,
      },
    });
  });

  it('preserves administrator provider config while preferring public capability flags', () => {
    const inbox = {
      id: 8,
      provider: 'connectapi',
      calls_supported: true,
      incoming_call_ring_enabled: true,
      provider_config: {
        instance_name: 'hub-call-test',
        calls_supported: false,
        incoming_call_ring_enabled: false,
      },
    };

    expect(buildCallInbox(inbox).provider_config).toEqual({
      instance_name: 'hub-call-test',
      calls_supported: true,
      incoming_call_ring_enabled: true,
    });
  });

  it('does not change non Connect API inboxes', () => {
    const inbox = { id: 9, provider: 'whatsapp_cloud' };

    expect(buildCallInbox(inbox)).toBe(inbox);
  });
});
