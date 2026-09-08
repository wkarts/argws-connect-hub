import { action } from '@storybook/addon-actions';
import HubDateRangePicker from '../DateRangePicker.vue';

export default {
  title: 'Components/Date Picker/Date Range Picker',
  argTypes: {
    confirmText: {
      defaultValue: 'Apply',
      control: {
        type: 'text',
      },
    },
    placeholder: {
      defaultValue: 'Select date range',
      control: {
        type: 'text',
      },
    },
    value: {
      control: {
        type: 'text',
      },
    },
  },
};

const Template = (args, { argTypes }) => ({
  props: Object.keys(argTypes),
  components: { HubDateRangePicker },
  template:
    '<hub-date-range-picker v-bind="$props" @change="onChange"></hub-date-range-picker>',
});

export const DateRangePicker = Template.bind({});
DateRangePicker.args = {
  onChange: action('applied'),
  value: new Date(),
};
