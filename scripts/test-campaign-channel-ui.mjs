import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = path => fs.readFileSync(path, 'utf8');

const locale = read('app/javascript/dashboard/i18n/locale/pt_BR/campaign.json');
const addCampaign = read(
  'app/javascript/dashboard/routes/dashboard/settings/campaigns/AddCampaign.vue'
);
const editCampaign = read(
  'app/javascript/dashboard/routes/dashboard/settings/campaigns/EditCampaign.vue'
);
const campaignMaterials = read(
  'app/javascript/dashboard/routes/dashboard/settings/campaigns/CampaignMaterials.vue'
);
const campaignsTable = read(
  'app/javascript/dashboard/routes/dashboard/settings/campaigns/CampaignsTable.vue'
);
const inboxStore = read('app/javascript/dashboard/store/modules/inboxes.js');

const genericEmptyState =
  'Por favor, crie uma caixa de entrada e comece a adicionar campanhas';

test('campaign empty states are channel agnostic', () => {
  assert.equal((locale.match(new RegExp(genericEmptyState, 'g')) || []).length, 2);
  assert.doesNotMatch(locale, /caixa de entrada SMS/);
  assert.doesNotMatch(locale, /caixa de entrada de website/);
});

test('one-off and recurring campaign screens use capability-based inboxes', () => {
  for (const source of [addCampaign, editCampaign, campaignsTable]) {
    assert.match(source, /getRecurringCampaignInboxes/);
    assert.match(source, /getCampaignInboxes/);
  }
  assert.match(inboxStore, /getRecurringCampaignInboxes/);
  assert.match(inboxStore, /campaign_capabilities/);
});

test('WhatsApp campaign composer supports template and freeform delivery', () => {
  for (const source of [addCampaign, editCampaign]) {
    assert.match(source, /Mensagem livre/);
    assert.match(source, /value="template"/);
    assert.match(source, /getWhatsAppCampaignTemplates/);
    assert.match(source, /delivery_mode: 'freeform'/);
    assert.match(source, /delivery_mode: 'template'/);
    assert.match(source, /janela de atendimento/);
    assert.match(source, /campaign_type: this\.campaignType/);
  }
});

test('every campaign composer persists date and time', () => {
  for (const source of [addCampaign, editCampaign]) {
    assert.match(source, /scheduledAt: \{ required \}/);
    assert.match(source, /scheduled_at: this\.scheduledAt/);
    assert.match(source, /Data e hora da campanha/);
    assert.match(source, /Informe a data e a hora da campanha/);
  }
});

test('recurring outbound campaigns expose cadence controls', () => {
  for (const source of [addCampaign, editCampaign]) {
    assert.match(source, /recurrenceFrequency/);
    assert.match(source, /recurrenceInterval/);
    assert.match(source, /recurrenceEndsAt/);
    assert.match(source, /frequency: this\.recurrenceFrequency/);
    assert.match(source, /interval: Number\(this\.recurrenceInterval\)/);
    assert.match(source, /ends_at: this\.recurrenceEndsAt/);
  }
});

test('campaign materials use unrestricted direct uploads and persist blob ids', () => {
  assert.match(campaignMaterials, /DirectUpload/);
  assert.match(campaignMaterials, /type="file"/);
  assert.match(campaignMaterials, /multiple/);
  assert.match(campaignMaterials, /active_storage\/direct_uploads/);
  assert.doesNotMatch(campaignMaterials, /accept=/);

  for (const source of [addCampaign, editCampaign]) {
    assert.match(source, /CampaignMaterials/);
    assert.match(source, /material_blob_ids/);
    assert.match(source, /material\.signed_id/);
  }
});
