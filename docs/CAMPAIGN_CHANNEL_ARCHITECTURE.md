# Campaign channel architecture

Campaigns use a single orchestration model and resolve delivery by the selected inbox channel. Supported outbound inboxes can operate as either one-off (`one_off`) or recurring/ongoing (`ongoing`) campaigns; Website keeps its existing recurring page-triggered behavior.

## Flow

1. `Campaign#trigger!` selects the campaign execution mode.
2. One-off campaigns delegate to `Campaigns::OneoffCampaignService`; recurring outbound campaigns delegate to `Campaigns::RecurringCampaignService`.
3. Both reuse `Campaigns::AudienceCampaignService` for audience resolution and contact iteration.
4. `Campaigns::ChannelDriverResolver` selects the delivery driver from the inbox.
5. Audience selection remains label-based for outbound channels.
6. The driver decides whether a contact is deliverable and delegates to the channel's existing delivery pipeline.
7. One-off campaigns are completed after dispatch starts; recurring campaigns remain active so they can be triggered again.

## Inbox campaign modes

The inbox API exposes `campaign_capabilities.modes` and is the source of truth for campaign availability in the frontend.

- Website: `ongoing` only, preserving URL/time-on-page triggers.
- SMS: `one_off`, `ongoing`.
- Twilio SMS: `one_off`, `ongoing`.
- WhatsApp / Connect|API: `one_off`, `ongoing`.
- E-mail: `one_off`, `ongoing`.
- API / Webhook: `one_off`, `ongoing`.

Adding another outbound channel requires registering a driver in `Campaigns::ChannelDriverResolver`; the campaign screens then consume the capability reported by the backend instead of hard-coding a channel name.

## Drivers

- `Channel::Sms`: text through the existing SMS channel.
- `Channel::TwilioSms`: text through the existing Twilio SMS channel.
- `Channel::Whatsapp`: creates an auditable `Conversation`/`Message`; `SendReplyJob` and `Whatsapp::SendOnWhatsappService` perform the actual provider delivery.
- `Channel::Email`: creates an auditable `Conversation`/`Message`; `EmailReplyWorker` performs delivery. The campaign subject is stored in `message_attributes.subject` and copied to `conversation.additional_attributes.mail_subject`.
- `Channel::Api`: creates an auditable `Conversation`/`Message`; the existing `WebhookListener` delivers `message_created` to the inbox `webhook_url`.

## WhatsApp: template or freeform

WhatsApp campaigns support two delivery modes:

- `template`: uses an approved/available template from the selected inbox/Connect|API instance.
- `freeform`: sends the campaign text through the normal channel `send_message` path without requiring a template.

Freeform mode is intentionally allowed for campaigns even when there is no open reply window. The UI shows a warning that final acceptance depends on the instance/provider/channel rules; delivery errors remain recorded on the generated `Message`. This exception is scoped to campaign messages. Normal manual new-conversation opening continues to require its configured opening template.

Campaign template eligibility uses the full template catalog available for the selected Connect|API instance. It does **not** depend on `hub_opening_enabled`; that flag remains scoped only to the normal new-conversation opening flow.

A selected campaign template must be present and available for the selected instance. Local Connect|API templates retain their version and rendered-content validation through `ConnectApi::LocalTemplateMessage`.

## Persistence

Channel-specific compositor data is stored in `campaigns.message_attributes` (`jsonb`). The same persisted attributes are reused on recurring deliveries. This keeps the campaign schema extensible without adding one database column for every outbound channel.

Examples:

```json
{
  "subject": "Atualização mensal"
}
```

```json
{
  "delivery_mode": "freeform"
}
```

```json
{
  "delivery_mode": "template",
  "template_params": {
    "name": "billing_notice",
    "language": "pt_BR",
    "connect_api_version": 3,
    "processed_params": {
      "1": "Wallace"
    }
  }
}
```

## Compatibility

The legacy `Sms::OneoffSmsCampaignService` and `Twilio::OneoffSmsCampaignService` remain compatibility adapters. Existing Website recurring campaigns keep their URL/time-on-page model. Outbound campaigns created without an explicit `campaign_type` retain the legacy one-off default, while the updated UI sends the selected mode explicitly.
