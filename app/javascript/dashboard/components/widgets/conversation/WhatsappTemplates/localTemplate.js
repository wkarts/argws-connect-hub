export const isLocalTemplate = template =>
  template?.source === 'connectapi_local';

export const localTemplateAvailable = template =>
  isLocalTemplate(template) &&
  template.status === 'LOCAL_READY' &&
  template.execution === 'rendered_text' &&
  template.meta_approved === false &&
  template.enabled === true &&
  template.available === true &&
  Number.isSafeInteger(template.version) && template.version > 0;

// Static text header/footer are part of the actual delivered local model.
export const localTemplateText = template =>
  ['HEADER', 'BODY', 'FOOTER']
    .map(type => template.components?.find(component => component.type === type)?.text)
    .filter(value => typeof value === 'string')
    .join('\n\n');
