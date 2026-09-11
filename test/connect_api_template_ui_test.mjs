import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';
const base = new URL('../app/javascript/dashboard/components/widgets/conversation/WhatsappTemplates/', import.meta.url);
const source = fs.readFileSync(new URL('templateAvailability.js', base), 'utf8');
const { isTemplateReady } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const local = {
  origin: 'CONNECT_LOCAL', id: 'local_one', revision: 1, status: 'LOCAL_READY',
  enabled: true, available: true, meta_approved: false,
  name: 'hello', language: 'pt_BR', category: 'UTILITY',
  components: [{ type: 'BODY', text: 'Olá!' }],
};
test('a local model is selectable only in Connect API', () => {
  assert.equal(isTemplateReady(local, true), true);
  assert.equal(isTemplateReady(local, false), false);
});
for (const changes of [{ enabled: false }, { available: false }, { status: 'LOCAL_DISABLED' }, { status: 'APPROVED' }, { revision: 0 }, { id: '123' }, { meta_approved: true }]) {
  test(`local selection fails closed for ${JSON.stringify(changes)}`, () => assert.equal(isTemplateReady({ ...local, ...changes }, true), false));
}
test('official approved and legacy blank-status behavior is preserved', () => {
  const official = { components: [], status: 'APPROVED' };
  assert.equal(isTemplateReady(official, false), true);
  assert.equal(isTemplateReady({ components: [] }, true), true);
  assert.equal(isTemplateReady({ components: [] }, false), false);
});
function parser(template) {
  const vue = fs.readFileSync(new URL('TemplateParser.vue', base), 'utf8');
  const script = vue.match(/<script>([\s\S]*?)<\/script>/)[1]
    .replace(/^import .*;$/gm, '').replace('export default', 'component =');
  const hooks = []; const events = [];
  const context = {
    component: null,
    ref: value => ({ value }),
    computed: getter => ({ get value() { return getter(); } }),
    onMounted: callback => hooks.push(callback),
    requiredIf: () => true,
    useVuelidate: () => ({ value: { $touch() {}, $invalid: false } }),
  };
  vm.createContext(context); vm.runInContext(script, context);
  const result = context.component.setup({ template }, { emit: (event, payload) => events.push({ event, payload }) });
  hooks.forEach(callback => callback());
  return { result, events };
}
test('parser emits local id and revision with hello (no variables)', () => {
  const { result, events } = parser(local); result.sendMessage();
  assert.equal(events[0].payload.templateParams.connect_template_id, 'local_one');
  assert.equal(events[0].payload.templateParams.connect_template_revision, 1);
  assert.equal(events[0].payload.message, 'Olá!');
});
test('parser emits the selected local body and parameters', () => {
  const { result, events } = parser({ ...local, components: [{ type: 'BODY', text: 'Olá, {{1}}!' }] });
  result.processedParams.value['1'] = 'Cliente'; result.sendMessage();
  assert.equal(events[0].payload.message, 'Olá, Cliente!');
  assert.equal(events[0].payload.templateParams.processed_params['1'], 'Cliente');
});
test('official parser payload is not polluted by local metadata', () => {
  const { result, events } = parser({ ...local, origin: 'META' }); result.sendMessage();
  assert.equal('connect_template_id' in events[0].payload.templateParams, false);
});
