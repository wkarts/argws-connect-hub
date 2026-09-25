<script>
export default {
  props: {
    app: { type: Object, required: true },
    size: { type: Number, default: 28 },
  },
  data() { return { failed: false }; },
  watch: { 'app.icon_url'() { this.failed = false; } },
};
</script>

<template>
  <span class="workspace-icon" :style="{ width: `${size}px`, height: `${size}px` }" aria-hidden="true">
    <img v-if="app.icon_url && !failed" :src="app.icon_url" alt="" draggable="false" referrerpolicy="no-referrer" @error="failed = true" />
    <fluent-icon v-else :icon="app.icon_name || 'globe'" :size="Math.min(size, 22)" />
  </span>
</template>

<style scoped>
.workspace-icon { display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; pointer-events: none; }
.workspace-icon img { display: block; width: 100%; height: 100%; object-fit: contain; }
</style>
