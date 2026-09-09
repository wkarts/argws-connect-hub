import { Plugin, PluginKey } from 'prosemirror-state';
import { Decoration, DecorationSet } from 'prosemirror-view';

let pluginSequence = 0;

export const triggerCharacters = trigger => ({ trigger });

const matchTrigger = (text, trigger) => {
  if (!trigger) return null;
  if (trigger === '{{') {
    const match = text.match(/(?:^|\s)(\{\{[^{}\n]*)$/);
    return match ? match[1] : null;
  }
  const escaped = trigger.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = text.match(new RegExp(`(?:^|\\s)(${escaped}[^\\s${escaped}]*)$`));
  return match ? match[1] : null;
};

export const suggestionsPlugin = ({
  matcher,
  suggestionClass = 'hub-editor-suggestion',
  onEnter = () => false,
  onChange = () => false,
  onExit = () => false,
  onKeyDown = () => false,
} = {}) => {
  const key = new PluginKey(`hub-suggestions-${pluginSequence++}`);
  let activeRange = null;
  let activeText = '';

  const resolve = view => {
    const { state } = view;
    const { selection } = state;
    if (!selection.empty) return null;
    const $from = selection.$from;
    const before = $from.parent.textBetween(0, $from.parentOffset, '\n', '\ufffc');
    const matchedText = matchTrigger(before, matcher?.trigger);
    if (!matchedText) return null;
    return {
      text: matchedText,
      range: {
        from: selection.from - matchedText.length,
        to: selection.from,
      },
      view,
    };
  };

  return new Plugin({
    key,
    state: {
      init: () => ({ range: null }),
      apply: (_tr, value) => value,
    },
    props: {
      decorations(state) {
        if (!activeRange || !suggestionClass) return null;
        if (activeRange.to > state.doc.content.size) return null;
        return DecorationSet.create(state.doc, [
          Decoration.inline(activeRange.from, activeRange.to, {
            class: suggestionClass,
          }),
        ]);
      },
      handleKeyDown(view, event) {
        if (!activeRange) return false;
        return Boolean(onKeyDown({ event, range: activeRange, view, text: activeText }));
      },
    },
    view(view) {
      const update = currentView => {
        const result = resolve(currentView);
        if (!result) {
          if (activeRange) onExit({ range: activeRange, view: currentView, text: activeText });
          activeRange = null;
          activeText = '';
          return;
        }
        const wasActive = Boolean(activeRange);
        activeRange = result.range;
        activeText = result.text;
        if (wasActive) onChange(result);
        else onEnter(result);
      };
      update(view);
      return {
        update(currentView) {
          update(currentView);
        },
        destroy() {
          if (activeRange) onExit({ range: activeRange, view, text: activeText });
          activeRange = null;
          activeText = '';
        },
      };
    },
  });
};
