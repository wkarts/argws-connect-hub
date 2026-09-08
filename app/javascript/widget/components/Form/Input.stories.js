import { action } from '@storybook/addon-actions';
import hubInput from './Input';

export default {
  title: 'Components/Form/Input',
  component: hubInput,
  argTypes: {
    label: {
      defaultValue: 'Email Address',
      control: {
        type: 'text',
      },
    },
    type: {
      defaultValue: 'email',
      control: {
        type: 'text',
      },
    },
    placeholder: {
      defaultValue: 'Please enter your email address',
      control: {
        type: 'text',
      },
    },
    value: {
      defaultValue: 'John12@ync.in',
      control: {
        type: 'text ,number',
      },
    },
    error: {
      defaultValue: '',
      control: {
        type: 'text',
      },
    },
  },
};

const Template = (args, { argTypes }) => ({
  props: Object.keys(argTypes),
  components: { hubInput },
  template: '<hub-input v-bind="$props" @input="onClick"></hub-input>',
});

export const Input = Template.bind({});
Input.args = {
  onClick: action('Added'),
};
