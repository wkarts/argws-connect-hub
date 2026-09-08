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
    key="inbox-reports"
    type="inbox"
    getter-key="inboxes/getInboxes"
    action-key="inboxes/get"
    :download-button-label="$t('INBOX_REPORTS.DOWNLOAD_INBOX_REPORTS')"
  />
</template>
