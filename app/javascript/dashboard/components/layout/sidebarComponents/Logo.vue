<script>
import { frontendURL } from 'dashboard/helper/URLHelper';

export default {
  props: {
    source: {
      type: String,
      default: '',
    },
    name: {
      type: String,
      default: '',
    },
    accountId: {
      type: Number,
      default: 0,
    },
  },
  computed: {
    dashboardPath() {
      return frontendURL(`accounts/${this.accountId}/dashboard`);
    },
    logoSource() {
      return this.source || '/brand-assets/logo_thumbnail.png';
    },
  },
};
</script>

<template>
  <div class="w-8 h-8">
    <router-link :to="dashboardPath" replace>
      <img
        :src="logoSource"
        :alt="name || 'HUB'"
        class="block h-8 w-8 object-contain"
      />
    </router-link>
  </div>
</template>
