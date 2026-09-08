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
    key="team-reports"
    type="team"
    getter-key="teams/getTeams"
    action-key="teams/get"
    :download-button-label="$t('TEAM_REPORTS.DOWNLOAD_TEAM_REPORTS')"
  />
</template>
