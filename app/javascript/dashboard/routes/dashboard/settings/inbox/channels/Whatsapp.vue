<script>
import PageHeader from '../../SettingsSubPageHeader.vue';
import ConnectApi from './ConnectApi.vue';
export default { components: { PageHeader, ConnectApi } };
</script>

<template>
  <div class="border border-slate-25 dark:border-slate-800/60 bg-white dark:bg-slate-900 h-full p-6 w-full max-w-full md:w-3/4 md:max-w-[75%] flex-shrink-0 flex-grow-0">
    <PageHeader :header-title="$t('INBOX_MGMT.ADD.WHATSAPP.TITLE')" header-content="WhatsApp via Connect|API — QR Code, código de pareamento e protocolo Meta-compatible." />
    <ConnectApi />
  </div>
</template>
