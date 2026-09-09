import MarkdownIt from 'markdown-it';
import { Schema } from 'prosemirror-model';
import { EditorState, Selection, Plugin } from 'prosemirror-state';
import { EditorView, Decoration, DecorationSet } from 'prosemirror-view';
import { MarkdownParser, MarkdownSerializer } from 'prosemirror-markdown';
import { keymap } from 'prosemirror-keymap';
import { baseKeymap, toggleMark, setBlockType } from 'prosemirror-commands';
import { history, undo, redo } from 'prosemirror-history';
import { dropCursor } from 'prosemirror-dropcursor';
import { gapCursor } from 'prosemirror-gapcursor';
import { addListNodes, wrapInList } from 'prosemirror-schema-list';
import { menuBar, MenuItem } from 'prosemirror-menu';

const baseNodes = {
  doc: { content: 'block+' },
  paragraph: {
    content: 'inline*',
    group: 'block',
    parseDOM: [{ tag: 'p' }],
    toDOM: () => ['p', 0],
  },
  blockquote: {
    content: 'block+',
    group: 'block',
    defining: true,
    parseDOM: [{ tag: 'blockquote' }],
    toDOM: () => ['blockquote', 0],
  },
  horizontal_rule: {
    group: 'block',
    parseDOM: [{ tag: 'hr' }],
    toDOM: () => ['hr'],
  },
  heading: {
    attrs: { level: { default: 1 } },
    content: 'inline*',
    group: 'block',
    defining: true,
    parseDOM: [1, 2, 3, 4, 5, 6].map(level => ({
      tag: `h${level}`,
      attrs: { level },
    })),
    toDOM: node => [`h${node.attrs.level}`, 0],
  },
  code_block: {
    content: 'text*',
    marks: '',
    group: 'block',
    code: true,
    defining: true,
    parseDOM: [{ tag: 'pre', preserveWhitespace: 'full' }],
    toDOM: () => ['pre', ['code', 0]],
  },
  text: { group: 'inline' },
  image: {
    inline: true,
    attrs: {
      src: {},
      alt: { default: null },
      title: { default: null },
      height: { default: null },
    },
    group: 'inline',
    draggable: true,
    parseDOM: [{
      tag: 'img[src]',
      getAttrs: dom => ({
        src: dom.getAttribute('src'),
        title: dom.getAttribute('title'),
        alt: dom.getAttribute('alt'),
        height: dom.style.height || dom.getAttribute('height') || null,
      }),
    }],
    toDOM: node => {
      const attrs = { src: node.attrs.src, alt: node.attrs.alt, title: node.attrs.title };
      if (node.attrs.height) attrs.style = `height: ${node.attrs.height};`;
      return ['img', attrs];
    },
  },
  hard_break: {
    inline: true,
    group: 'inline',
    selectable: false,
    parseDOM: [{ tag: 'br' }],
    toDOM: () => ['br'],
  },
  mention: {
    inline: true,
    group: 'inline',
    atom: true,
    selectable: true,
    attrs: {
      userId: {},
      userFullName: { default: '' },
    },
    parseDOM: [{
      tag: 'span[data-hub-mention-id]',
      getAttrs: dom => ({
        userId: dom.getAttribute('data-hub-mention-id'),
        userFullName: dom.getAttribute('data-hub-mention-name') || dom.textContent.replace(/^@/, ''),
      }),
    }],
    toDOM: node => [
      'span',
      {
        class: 'hub-editor-mention',
        'data-hub-mention-id': node.attrs.userId,
        'data-hub-mention-name': node.attrs.userFullName,
      },
      `@${node.attrs.userFullName}`,
    ],
  },
};

const marks = {
  link: {
    attrs: { href: {}, title: { default: null } },
    inclusive: false,
    parseDOM: [{
      tag: 'a[href]',
      getAttrs: dom => ({ href: dom.getAttribute('href'), title: dom.getAttribute('title') }),
    }],
    toDOM: node => ['a', node.attrs, 0],
  },
  em: {
    parseDOM: [{ tag: 'i' }, { tag: 'em' }, { style: 'font-style=italic' }],
    toDOM: () => ['em', 0],
  },
  strong: {
    parseDOM: [
      { tag: 'strong' },
      { tag: 'b', getAttrs: node => node.style.fontWeight !== 'normal' && null },
      { style: 'font-weight', getAttrs: value => /^(bold(er)?|[5-9]\d{2,})$/.test(value) && null },
    ],
    toDOM: () => ['strong', 0],
  },
  code: {
    parseDOM: [{ tag: 'code' }],
    toDOM: () => ['code', 0],
  },
};

const nodesWithLists = addListNodes(baseNodes, 'paragraph block*', 'block');
export const messageSchema = new Schema({ nodes: nodesWithLists, marks });
export const fullSchema = messageSchema;

const mentionMarkdownPlugin = md => {
  md.inline.ruler.before('link', 'hub_mention', (state, silent) => {
    const source = state.src.slice(state.pos, state.posMax);
    const match = source.match(/^\[([^\]]+)\]\(mention:\/\/user\/(\d+)\/([^\)]+)\)/);
    if (!match) return false;
    if (!silent) {
      const token = state.push('hub_mention', '', 0);
      token.meta = {
        userId: match[2],
        userFullName: decodeURIComponent(match[3]).replace(/^@/, ''),
      };
      token.content = match[1];
    }
    state.pos += match[0].length;
    return true;
  });
};

const markdown = new MarkdownIt('commonmark', { html: false, linkify: true, breaks: false });
markdown.use(mentionMarkdownPlugin);

const tokenMap = {
  blockquote: { block: 'blockquote' },
  paragraph: { block: 'paragraph' },
  list_item: { block: 'list_item' },
  bullet_list: { block: 'bullet_list' },
  ordered_list: { block: 'ordered_list', getAttrs: token => ({ order: +(token.attrGet('start') || 1) }) },
  heading: { block: 'heading', getAttrs: token => ({ level: +token.tag.slice(1) }) },
  code_block: { block: 'code_block', noCloseToken: true },
  fence: { block: 'code_block', getAttrs: () => ({ params: '' }), noCloseToken: true },
  hr: { node: 'horizontal_rule' },
  image: {
    node: 'image',
    getAttrs: token => {
      const src = token.attrGet('src') || '';
      let height = null;
      try {
        const url = new URL(src, 'https://hub.invalid');
        height = url.searchParams.get('hub_image_height');
      } catch (_error) {
        const match = src.match(/[?&]hub_image_height=([^&#]+)/);
        height = match ? decodeURIComponent(match[1]) : null;
      }
      return { src, title: token.attrGet('title') || null, alt: token.children?.[0]?.content || token.content || null, height };
    },
  },
  hardbreak: { node: 'hard_break' },
  softbreak: { node: 'hard_break' },
  em: { mark: 'em' },
  strong: { mark: 'strong' },
  link: { mark: 'link', getAttrs: token => ({ href: token.attrGet('href'), title: token.attrGet('title') || null }) },
  code_inline: { mark: 'code', noCloseToken: true },
  hub_mention: { node: 'mention', getAttrs: token => token.meta },
};

const parserFor = schema => new MarkdownParser(schema, markdown, tokenMap);

const serializer = new MarkdownSerializer(
  {
    blockquote(state, node) { state.wrapBlock('> ', null, node, () => state.renderContent(node)); },
    code_block(state, node) { state.write('```\n'); state.text(node.textContent, false); state.ensureNewLine(); state.write('```'); state.closeBlock(node); },
    heading(state, node) { state.write(`${'#'.repeat(node.attrs.level)} `); state.renderInline(node); state.closeBlock(node); },
    horizontal_rule(state, node) { state.write('---'); state.closeBlock(node); },
    bullet_list(state, node) { state.renderList(node, '  ', () => `${node.attrs.bullet || '*'} `); },
    ordered_list(state, node) { const start = node.attrs.order || 1; const maxW = String(start + node.childCount - 1).length; const space = ' '.repeat(maxW + 2); state.renderList(node, space, index => `${String(start + index).padStart(maxW, ' ')}. `); },
    list_item(state, node) { state.renderContent(node); },
    paragraph(state, node) { state.renderInline(node); state.closeBlock(node); },
    image(state, node) {
      const alt = node.attrs.alt || '';
      const title = node.attrs.title ? ` \"${String(node.attrs.title).replace(/"/g, '\\"')}\"` : '';
      let src = node.attrs.src || '';
      if (node.attrs.height) {
        const separator = src.includes('?') ? '&' : '?';
        src = src.replace(/([?&])hub_image_height=[^&#]*&?/, '$1').replace(/[?&]$/, '');
        src = `${src}${src.includes('?') ? '&' : separator}hub_image_height=${encodeURIComponent(node.attrs.height)}`;
      }
      state.write(`![${alt}](${src}${title})`);
    },
    hard_break(state, node, parent, index) {
      for (let i = index; i < parent.childCount; i += 1) if (parent.child(i).type !== node.type) { state.write('\\\n'); return; }
    },
    text(state, node) { state.text(node.text); },
    mention(state, node) {
      const name = node.attrs.userFullName || '';
      state.write(`[@${name}](mention://user/${node.attrs.userId}/${encodeURIComponent(name)})`);
    },
  },
  {
    em: { open: '*', close: '*', mixable: true, expelEnclosingWhitespace: true },
    strong: { open: '**', close: '**', mixable: true, expelEnclosingWhitespace: true },
    link: { open: '[', close: state => `](${state.mark.attrs.href}${state.mark.attrs.title ? ` \"${state.mark.attrs.title}\"` : ''})`, mixable: false },
    code: { open: '`', close: '`', escape: false },
  }
);

export class MessageMarkdownTransformer {
  constructor(schema = messageSchema) { this.parser = parserFor(schema); }
  parse(content = '') {
    const text = String(content || '');
    return this.parser.parse(text || '');
  }
}

export class ArticleMarkdownTransformer {
  constructor(schema = fullSchema) { this.parser = parserFor(schema); }
  parse(content = '') { return this.parser.parse(String(content || '')); }
}

export const MessageMarkdownSerializer = { serialize: doc => serializer.serialize(doc) };
export const ArticleMarkdownSerializer = MessageMarkdownSerializer;

const markActive = (state, type) => {
  const { from, $from, to, empty } = state.selection;
  if (empty) return Boolean(type.isInSet(state.storedMarks || $from.marks()));
  return state.doc.rangeHasMark(from, to, type);
};

const commandItem = (label, command, active) => new MenuItem({
  label,
  run: command,
  enable: state => command(state),
  active,
});

const linkCommand = schema => (state, dispatch) => {
  const mark = schema.marks.link;
  if (!mark) return false;
  if (!dispatch) return true;
  const current = mark.isInSet(state.storedMarks || state.selection.$from.marks());
  if (current) return toggleMark(mark)(state, dispatch);
  const href = typeof window !== 'undefined' ? window.prompt('URL') : null;
  if (!href) return false;
  return toggleMark(mark, { href })(state, dispatch);
};

const menuItems = ({ schema, methods = {}, enabledMenuOptions = [] }) => {
  const allowed = new Set(enabledMenuOptions || []);
  const items = [];
  const add = (name, item) => { if (!allowed.size || allowed.has(name)) items.push(item); };
  if (schema.marks.strong) add('strong', commandItem('B', toggleMark(schema.marks.strong), state => markActive(state, schema.marks.strong)));
  if (schema.marks.em) add('em', commandItem('I', toggleMark(schema.marks.em), state => markActive(state, schema.marks.em)));
  if (schema.marks.code) add('code', commandItem('</>', toggleMark(schema.marks.code), state => markActive(state, schema.marks.code)));
  if (schema.marks.link) add('link', commandItem('Link', linkCommand(schema), state => markActive(state, schema.marks.link)));
  if (schema.nodes.bullet_list) add('bulletList', commandItem('• List', wrapInList(schema.nodes.bullet_list)));
  if (schema.nodes.ordered_list) add('orderedList', commandItem('1. List', wrapInList(schema.nodes.ordered_list)));
  [1, 2, 3].forEach(level => {
    if (schema.nodes.heading) add(`h${level}`, commandItem(`H${level}`, setBlockType(schema.nodes.heading, { level })));
  });
  add('imageUpload', new MenuItem({ label: 'Image', run: () => { methods.onImageUpload?.(); return true; } }));
  add('undo', commandItem('Undo', undo));
  add('redo', commandItem('Redo', redo));
  return items;
};

const placeholderPlugin = placeholder => new Plugin({
  props: {
    attributes: { class: 'ProseMirror-hub-style', 'data-placeholder': placeholder || '' },
    decorations(state) {
      if (!placeholder || state.doc.textContent || state.doc.childCount !== 1) return null;
      return DecorationSet.create(state.doc, [
        Decoration.node(0, state.doc.content.size, { class: 'hub-editor-empty' }),
      ]);
    },
  },
});

export const buildEditor = ({ schema, placeholder = '', methods = {}, plugins = [], enabledMenuOptions = [] } = {}) => {
  const result = [
    history(),
    keymap({ 'Mod-z': undo, 'Shift-Mod-z': redo, 'Mod-y': redo }),
    keymap(baseKeymap),
    dropCursor(),
    gapCursor(),
    placeholderPlugin(placeholder),
    ...(plugins || []),
  ];
  const content = menuItems({ schema, methods, enabledMenuOptions });
  if (content.length) result.push(menuBar({ content: [content], floating: false }));
  return result;
};

export { EditorState, EditorView, Selection };
