<script>
export default {
  props: { message: { type: String, required: true }, busy: Boolean },
};
</script>
<template>
  <hub-modal :show="true" :on-close="() => $emit('cancel')">
    <div class="p-6">
      <h3 class="text-base font-semibold">{{ $t('GROUP_MANAGEMENT.CONFIRM_TITLE') }}</h3>
      <p class="my-4 whitespace-pre-line">{{ message }}</p>
      <div class="flex justify-end gap-2">
        <hub-button variant="clear" :disabled="busy" @click="$emit('cancel')">{{ $t('GROUP_MANAGEMENT.CANCEL') }}</hub-button>
        <hub-button :disabled="busy" @click="$emit('confirm')">{{ $t('GROUP_MANAGEMENT.CONFIRM') }}</hub-button>
      </div>
    </div>
  </hub-modal>
</template>
