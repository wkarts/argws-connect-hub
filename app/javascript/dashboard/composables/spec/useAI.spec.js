import { useAI } from '../useAI';
import {
  useStore,
  useStoreGetters,
  useMapGetter,
} from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from '../useI18n';
import OpenAPI from 'dashboard/api/integrations/openapi';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables');
vi.mock('../useI18n');
vi.mock('dashboard/api/integrations/openapi');

describe('useAI', () => {
  const mockStore = {
    dispatch: vi.fn(),
  };

  const mockGetters = {
    'integrations/getUIFlags': { value: { isFetching: false } },
    'draftMessages/get': { value: () => 'Draft message' },
  };

  beforeEach(() => {
    vi.clearAllMocks();
    useStore.mockReturnValue(mockStore);
    useStoreGetters.mockReturnValue(mockGetters);
    useMapGetter.mockImplementation(getter => {
      const mockValues = {
        'integrations/getAppIntegrations': [],
        getSelectedChat: { id: '123' },
        'draftMessages/getReplyEditorMode': 'reply',
      };
      return { value: mockValues[getter] };
    });
    useI18n.mockReturnValue({ t: vi.fn() });
    useAlert.mockReturnValue(vi.fn());
  });

  it('initializes computed properties correctly', async () => {
    const { uiFlags, appIntegrations, currentChat, replyMode, draftMessage } =
      useAI();

    expect(uiFlags.value).toEqual({ isFetching: false });
    expect(appIntegrations.value).toEqual([]);
    expect(currentChat.value).toEqual({ id: '123' });
    expect(replyMode.value).toBe('reply');
    expect(draftMessage.value).toBe('Draft message');
  });

  it('fetches integrations if required', async () => {
    const { fetchIntegrationsIfRequired } = useAI();
    await fetchIntegrationsIfRequired();
    expect(mockStore.dispatch).toHaveBeenCalledWith('integrations/get');
  });

  it('does not fetch integrations if already loaded', async () => {
    useMapGetter.mockImplementation(getter => {
      const mockValues = {
        'integrations/getAppIntegrations': [{ id: 'openai' }],
        getSelectedChat: { id: '123' },
        'draftMessages/getReplyEditorMode': 'reply',
      };
      return { value: mockValues[getter] };
    });

    const { fetchIntegrationsIfRequired } = useAI();
    await fetchIntegrationsIfRequired();
    expect(mockStore.dispatch).not.toHaveBeenCalled();
  });


  it('fetches label suggestions', async () => {
    OpenAPI.processEvent.mockResolvedValue({
      data: { message: 'label1, label2' },
    });

    useMapGetter.mockImplementation(getter => {
      const mockValues = {
        'integrations/getAppIntegrations': [
          { id: 'openai', hooks: [{ id: 'hook1' }] },
        ],
        getSelectedChat: { id: '123' },
      };
      return { value: mockValues[getter] };
    });

    const { fetchLabelSuggestions } = useAI();
    const result = await fetchLabelSuggestions();

    expect(OpenAPI.processEvent).toHaveBeenCalledWith({
      type: 'label_suggestion',
      hookId: 'hook1',
      conversationId: '123',
    });

    expect(result).toEqual(['label1', 'label2']);
  });
});
