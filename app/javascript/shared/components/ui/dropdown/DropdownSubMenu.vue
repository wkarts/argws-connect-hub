<script>
import HubDropdownHeader from 'shared/components/ui/dropdown/DropdownHeader.vue';

export default {
  name: 'HubDropdownMenu',
  componentName: 'HubDropdownMenu',

  components: {
    HubDropdownHeader,
  },
  props: {
    title: {
      type: String,
      default: '',
    },
  },
};
</script>

<template>
  <li class="sub-menu-container">
    <ul class="sub-menu-li-container">
      <HubDropdownHeader v-if="title" :title="title" />
      <slot />
    </ul>
  </li>
</template>

<style lang="scss" scoped>
.sub-menu-container {
  margin-top: var(--space-micro);
}

.sub-menu-li-container {
  margin: 0;
}
</style>
