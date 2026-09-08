<script>
export default {
  methods: {
    onClickNotes() {
      this.$emit('notes');
    },

    onClickEvents() {
      this.$emit('events');
    },

    onClickConversation() {
      this.$emit('conversation');
    },
  },
};
</script>

<template>
  <div class="wrap">
    <div class="header">
      <h5 class="text-lg text-black-900 dark:text-slate-200">
        {{ $t('EVENTS.HEADER.TITLE') }}
      </h5>
    </div>
    <div class="button-wrap">
      <hub-button
        variant="hollow"
        size="tiny"
        color-scheme="secondary"
        class-names="pill-button"
        @click="onClickNotes"
      >
        {{ $t('EVENTS.BUTTON.PILL_BUTTON_NOTES') }}
      </hub-button>
      <hub-button
        variant="hollow"
        size="tiny"
        color-scheme="secondary"
        class-names="pill-button"
        @click="onClickEvents"
      >
        {{ $t('EVENTS.BUTTON.PILL_BUTTON_EVENTS') }}
      </hub-button>
      <hub-button
        variant="hollow"
        size="tiny"
        color-scheme="secondary"
        class-names="pill-button"
        @click="onClickConversation"
      >
        {{ $t('EVENTS.BUTTON.PILL_BUTTON_CONVO') }}
      </hub-button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.wrap {
  width: 100%;
  padding: var(--space-normal);

  .button-wrap {
    display: flex;

    .pill-button {
      margin-right: var(--space-small);
    }
  }
}
</style>
