<script>
export default {
  props: {
    app: { type: Object, required: true },
    size: { type: Number, default: 28 },
  },
  data() {
    return {
      manualFailed: false,
      faviconFailed: false,
    };
  },
  computed: {
    faviconUrl() {
      try {
        const url = new URL(this.app.url, window.location.origin);
        if (url.protocol !== 'https:') return '';
        return `${url.origin}/favicon.ico`;
      } catch (_) {
        return '';
      }
    },
  },
  watch: {
    'app.icon_url'() {
      this.manualFailed = false;
    },
    'app.url'() {
      this.faviconFailed = false;
    },
  },
};
</script>

<template>
  <span
    class="workspace-icon"
    :style="{ width: `${size}px`, height: `${size}px` }"
    aria-hidden="true"
  >
    <img
      v-if="app.icon_url && !manualFailed"
      :src="app.icon_url"
      alt=""
      draggable="false"
      referrerpolicy="no-referrer"
      @error="manualFailed = true"
    />
    <img
      v-else-if="faviconUrl && !faviconFailed"
      :src="faviconUrl"
      alt=""
      draggable="false"
      referrerpolicy="no-referrer"
      @error="faviconFailed = true"
    />
    <fluent-icon
      v-else
      :icon="app.icon_name || 'globe'"
      :size="Math.min(size, 22)"
    />
  </span>
</template>

<style scoped>
.workspace-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  pointer-events: none;
}
.workspace-icon img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
}
</style>
