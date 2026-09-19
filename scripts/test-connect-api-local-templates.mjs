import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
const dir = 'app/javascript/dashboard/components/widgets/conversation/WhatsappTemplates/';
const source = fs.readFileSync(`${dir}localTemplate.js`, 'utf8');
const { isLocalTemplate, localTemplateAvailable, localTemplateText } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const hubUtilsSource = fs.readFileSync('packages/hub-utils/src/index.js', 'utf8');
const { resolveTemplateVariables } = await import(`data:text/javascript;base64,${Buffer.from(hubUtilsSource).toString('base64')}`);
const local = { source: 'connectapi_local', execution: 'rendered_text', approved: true, enabled: true, available: true, status: 'APPROVED', category: 'OPENING', version: 1,
  components: [{ type: 'BODY', text: 'Olá {{1}}' }, { type: 'FOOTER', text: 'Equipe' }, { type: 'HEADER', text: 'Suporte' }] };
test('Connect API catalog requires approved status, availability and revision', () => {
  assert.ok(isLocalTemplate(local)); assert.ok(localTemplateAvailable(local));
  for (const key of ['source', 'execution', 'approved', 'enabled', 'available', 'status', 'version']) {
    const copy = { ...local }; delete copy[key]; assert.equal(localTemplateAvailable(copy), false, key);
  }
  assert.equal(localTemplateAvailable({ ...local, status: 'PENDING' }), false);
  assert.equal(localTemplateAvailable({ ...local, approved: false }), false);
});
test('preview matches header body footer render order and no extra data', () => {
  assert.equal(localTemplateText(local), 'Suporte\n\nOlá {{1}}\n\nEquipe');
});
test('picker and parser keep template branch and attach local version only', () => {
  const picker = fs.readFileSync(`${dir}TemplatesPicker.vue`, 'utf8');
  const parser = fs.readFileSync(`${dir}TemplateParser.vue`, 'utf8');
  assert.match(picker, /this.isConnectApi && localTemplateAvailable\(template\)/);
  assert.match(picker, /Abertura de conversa/);
  assert.match(parser, /isLocalTemplate\(props.template\) \? \{ connect_api_version: props.template.version \} : \{\}/);
  assert.match(parser, /localTemplateText\(props.template\)/);
});
test('reconcile notification describes empty catalog instead of claiming template availability', () => {
  const config = fs.readFileSync('app/javascript/dashboard/routes/dashboard/settings/inbox/settingsPage/ConnectApiConfiguration.vue', 'utf8');
  assert.match(config, /Nenhum template foi retornado/);
  assert.doesNotMatch(config, /Caixa e templates reconciliados com/);
});

test('HUB variables resolve atomically in template preview payload and positional parameters', () => {
  const resolved = resolveTemplateVariables({
    message: 'Olá! {{contact.name}}',
    templateParams: {
      name: 'hello',
      language: 'pt_BR',
      processed_params: { '1': '{{contact.name}}', '2': 'ID {{conversation.id}}' },
    },
    variables: {
      'contact.name': 'Maria da Silva',
      'conversation.id': 42,
    },
  });
  assert.equal(resolved.message, 'Olá! Maria da Silva');
  assert.deepEqual(resolved.templateParams.processed_params, {
    '1': 'Maria da Silva',
    '2': 'ID 42',
  });
  assert.deepEqual(resolved.unresolvedVariables, []);
});

test('HUB template variables fail closed in UI when a required value is unavailable', () => {
  const resolved = resolveTemplateVariables({
    message: 'Olá! {{contact.email}}',
    templateParams: {
      processed_params: { '1': '{{contact.email}}' },
    },
    variables: { 'contact.email': '' },
  });
  assert.equal(resolved.message, 'Olá! {{contact.email}}');
  assert.equal(resolved.templateParams.processed_params['1'], '{{contact.email}}');
  assert.deepEqual(resolved.unresolvedVariables, ['contact.email']);

  const replyBox = fs.readFileSync('app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue', 'utf8');
  const conversationForm = fs.readFileSync('app/javascript/dashboard/routes/dashboard/conversation/contact/ConversationForm.vue', 'utf8');
  assert.match(replyBox, /resolveTemplateVariables\(/);
  assert.match(conversationForm, /resolveTemplateVariables\(/);
  assert.match(replyBox, /unresolvedVariables\.length/);
  assert.match(conversationForm, /unresolvedVariables\.length/);
});
