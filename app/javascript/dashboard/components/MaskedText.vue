<script>
import 'highlight.js/styles/default.css';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';

export default {
  props: {
    value: {
      type: String,
      default: '',
    },
  },
  data() {
    return {
      masked: true,
    };
  },
  methods: {
    async onCopy(e) {
      e.preventDefault();
      await copyTextToClipboard(this.value);
      useAlert(this.$t('COMPONENTS.CODE.COPY_SUCCESSFUL'));
    },
    toggleMasked() {
      this.masked = !this.masked;
    },
  },
};
</script>

<template>
  <div class="text--container">
    <hub-button size="small" class="button--text" @click="onCopy">
      {{ $t('COMPONENTS.CODE.BUTTON_TEXT') }}
    </hub-button>
    <hub-button
      variant="clear"
      size="small"
      class="button--visibility"
      color-scheme="secondary"
      :icon="masked ? 'eye-show' : 'eye-hide'"
      @click.prevent="toggleMasked"
    />
    <highlightjs v-if="value" :code="masked ? '•'.repeat(10) : value" />
  </div>
</template>

<style lang="scss" scoped>
.text--container {
  position: relative;
  text-align: left;

  .button--text,
  .button--visibility {
    margin-top: 0;
    position: absolute;
    right: 0;
  }

  .button--visibility {
    right: 60px;
  }
}
</style>
