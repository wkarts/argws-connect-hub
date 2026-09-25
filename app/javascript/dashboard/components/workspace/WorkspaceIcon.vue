<script>
export default {
  props: { app: { type: Object, required: true } },
  data() { return { failed: false }; },
  watch: { 'app.icon_url'() { this.failed = false; } },
};
</script>

<template>
  <img
    v-if="app.icon_url && !failed"
    :src="app.icon_url"
    alt=""
    class="workspace-icon"
    referrerpolicy="no-referrer"
    @error="failed = true"
  />
  <fluent-icon v-else :icon="app.icon_name || 'globe'" size="22" />
</template>

<style scoped>
.workspace-icon { width: 22px; height: 22px; object-fit: contain; }
</style>
