import HubKeyboardShortcutModal from './HubKeyShortcutModal.vue';

export default {
  title: 'Components/Shortcuts/Keyboard Shortcut',
  component: HubKeyboardShortcutModal,
  argTypes: {},
};

const Template = (args, { argTypes }) => ({
  props: Object.keys(argTypes),
  components: { HubKeyboardShortcutModal },
  template:
    '<hub-keyboard-shortcut-modal v-bind="$props"></hub-keyboard-shortcut-modal>',
});

export const KeyboardShortcut = Template.bind({});
KeyboardShortcut.args = {};
