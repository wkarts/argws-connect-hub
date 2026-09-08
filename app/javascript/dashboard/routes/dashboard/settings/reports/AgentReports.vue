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
    key="agent-reports"
    type="agent"
    getter-key="agents/getAgents"
    action-key="agents/get"
    :download-button-label="$t('REPORT.DOWNLOAD_AGENT_REPORTS')"
  />
</template>
