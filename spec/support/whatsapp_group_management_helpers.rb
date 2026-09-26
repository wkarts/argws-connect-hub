module WhatsappGroupManagementHelpers
  def group_value(group, id: SecureRandom.hex(12), kind: 'text', from_me: false, timestamp: Time.current.to_i)
    value = { contacts: [{ group_id: group.jid, group_subject: group.name, wa_id: '30001', profile: { name: 'Participante' } }],
              messages: [{ id: id, type: kind, timestamp: timestamp,
                connect_api: { remote_jid: group.jid, participant: '30001@lid', from_me: from_me, recovered: true },
                kind => kind == 'text' ? { body: 'Conteúdo protegido' } : { id: id, caption: 'Legenda' } }] }
    value.with_indifferent_access
  end

  def group_envelope(group, **options)
    value = group_value(group, **options)
    value[:metadata] = { display_phone_number: channel.phone_number.delete('+'), phone_number_id: channel.provider_config['phone_number_id'] }
    { object: 'whatsapp_business_account', entry: [{ changes: [{ field: 'messages', value: value }] }] }.with_indifferent_access
  end

  def new_group(treatment: 'management', jid: '120363000000000099@g.us', **attributes)
    WhatsappGroup.create!({ account: channel.account, inbox: channel.inbox, jid: jid, name: 'Grupo privado', treatment: treatment, selected: true }.merge(attributes))
  end
end
