<script>
import Response from './views/Response.vue';

export default {
  name: 'App',
  components: {
    Response,
  },
};
</script>

<template>
  <div id="app" class="hub-survey-wrap">
    <Response />
  </div>
</template>

<style lang="scss">
@import '~survey/assets/scss/hub.scss';
</style>
