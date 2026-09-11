export const isTemplateReady = (template, isConnectApi = false) => {
  if (!template || !Array.isArray(template.components)) return false;
  const status = String(template.status || '').trim();
  if (template.origin === 'CONNECT_LOCAL') {
    return (
      isConnectApi &&
      status === 'LOCAL_READY' &&
      template.enabled === true &&
      template.available === true &&
      template.meta_approved === false &&
      Number.isInteger(template.revision) &&
      template.revision > 0 &&
      typeof template.id === 'string' &&
      template.id.startsWith('local_')
    );
  }
  return status.toLowerCase() === 'approved' || (isConnectApi && !status);
};
