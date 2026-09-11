import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
const dir = 'app/javascript/dashboard/components/widgets/conversation/WhatsappTemplates/';
const source = fs.readFileSync(`${dir}localTemplate.js`, 'utf8');
const { isLocalTemplate, localTemplateAvailable, localTemplateText } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const local = { source: 'connectapi_local', execution: 'rendered_text', meta_approved: false, enabled: true, available: true, status: 'LOCAL_READY', version: 1,
  components: [{ type: 'BODY', text: 'Olá {{1}}' }, { type: 'FOOTER', text: 'Equipe' }, { type: 'HEADER', text: 'Suporte' }] };
test('local catalog requires source, no Meta approval, explicit local-ready status and revision', () => {
  assert.ok(isLocalTemplate(local)); assert.ok(localTemplateAvailable(local));
  for (const key of ['source', 'execution', 'meta_approved', 'enabled', 'available', 'status', 'version']) {
    const copy = { ...local }; delete copy[key]; assert.equal(localTemplateAvailable(copy), false, key);
  }
  assert.equal(localTemplateAvailable({ ...local, status: 'APPROVED' }), false);
  assert.equal(localTemplateAvailable({ ...local, meta_approved: true }), false);
});
test('preview matches header body footer render order and no extra data', () => {
  assert.equal(localTemplateText(local), 'Suporte\n\nOlá {{1}}\n\nEquipe');
});
test('picker and parser preserve official branch and attach local version only', () => {
  const picker = fs.readFileSync(`${dir}TemplatesPicker.vue`, 'utf8');
  const parser = fs.readFileSync(`${dir}TemplateParser.vue`, 'utf8');
  assert.match(picker, /this.isConnectApi && localTemplateAvailable\(template\)/);
  assert.match(picker, /=== 'approved'/);
  assert.match(parser, /isLocalTemplate\(props.template\) \? \{ connect_api_version: props.template.version \} : \{\}/);
  assert.match(parser, /localTemplateText\(props.template\)/);
});
test('reconcile notification describes empty catalog instead of claiming template availability', () => {
  const config = fs.readFileSync('app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConnectApiConfiguration.vue', 'utf8');
  assert.match(config, /Nenhum template foi retornado/);
  assert.doesNotMatch(config, /Caixa e templates reconciliados com/);
});
