# Campaign channel architecture

One-off campaigns use a single orchestration path and resolve delivery by the selected inbox channel.

## Flow

1. `Campaigns::TriggerOneoffCampaignJob` invokes `Campaign#trigger!`.
2. `Campaign#trigger!` delegates to `Campaigns::OneoffCampaignService`.
3. The executor resolves a driver through `Campaigns::ChannelDriverResolver`.
4. Audience selection remains label-based and is performed once by the common executor.
5. The driver decides whether a contact is deliverable and delegates to the channel's existing delivery pipeline.

## Drivers

- `Channel::Sms`: text through the existing SMS channel.
- `Channel::TwilioSms`: text through the existing Twilio SMS channel.
- `Channel::Whatsapp`: creates an auditable `Conversation`/`Message`; `SendReplyJob` and `Whatsapp::SendOnWhatsappService` perform the actual provider delivery.
- `Channel::Email`: creates an auditable `Conversation`/`Message`; `EmailReplyWorker` performs delivery. The campaign subject is stored in `message_attributes.subject` and copied to `conversation.additional_attributes.mail_subject`.
- `Channel::Api`: creates an auditable `Conversation`/`Message`; the existing `WebhookListener` delivers `message_created` to the inbox `webhook_url`.

## WhatsApp and Connect|API templates

Campaigns use the full template catalog available for the selected Connect|API instance. Campaign eligibility does **not** depend on `hub_opening_enabled`; that flag remains scoped to the new-conversation opening flow.

A campaign template must be present and available for the selected instance. Local Connect|API templates also retain their version and rendered-content validation through `ConnectApi::LocalTemplateMessage`.

## Persistence

Channel-specific compositor data is stored in `campaigns.message_attributes` (`jsonb`). This keeps the campaign schema extensible without adding one database column for every outbound channel.

Examples:

```json
{
  "subject": "Monthly update"
}
```

```json
{
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

The legacy `Sms::OneoffSmsCampaignService` and `Twilio::OneoffSmsCampaignService` remain as compatibility adapters and delegate to the common executor.
