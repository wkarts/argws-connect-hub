<script>
export default {
  props: {
    heading: {
      type: String,
      default: '',
    },
    content: {
      type: String,
      default: '',
    },
    active: {
      type: Boolean,
      default: false,
    },
    src: {
      type: String,
      default: '',
    },
  },
};
</script>

<template>
  <div
    class="flex flex-col min-w-[15rem] max-h-[21.25rem] max-w-[23.75rem] rounded-md border border-solid border-slate-75 dark:border-slate-600"
    :class="{
      'bg-hub-25 dark:bg-slate-700 border border-solid border-hub-300 dark:border-hub-400':
        active,
    }"
  >
    <div
      class="flex justify-between items-center px-2 w-full h-10 bg-slate-50 dark:bg-slate-900 rounded-t-[5px] border-b border-solid border-slate-50 dark:border-slate-600"
      :class="{
        'bg-hub-50 border-b border-solid border-hub-75 dark:border-hub-700':
          active,
      }"
    >
      <div class="flex items-center p-1 text-sm font-medium">{{ heading }}</div>
      <fluent-icon
        v-if="active"
        icon="checkmark-circle"
        type="solid"
        size="24"
        class="text-hub-500 dark:text-hub-500"
      />
    </div>
    <div
      class="text-slate-700 dark:text-slate-200 text-xs leading-[1.4] px-3 pt-3 pb-0 text-start"
    >
      {{ content }}
    </div>
    <div v-if="src" class="p-3">
      <img
        :src="src"
        class="border border-solid rounded-md"
        :class="
          active
            ? 'border-hub-75 dark:border-hub-700'
            : 'border-slate-50 dark:border-slate-600'
        "
      />
    </div>
    <slot v-else />
  </div>
</template>
