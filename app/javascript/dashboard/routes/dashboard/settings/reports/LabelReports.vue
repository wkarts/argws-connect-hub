<script>
import HubReports from './components/HubReports.vue';

export default {
  components: {
    HubReports,
  },
};
</script>

<template>
  <HubReports
    key="label-reports"
    type="label"
    getter-key="labels/getLabels"
    action-key="labels/get"
    :download-button-label="$t('LABEL_REPORTS.DOWNLOAD_LABEL_REPORTS')"
  />
</template>
