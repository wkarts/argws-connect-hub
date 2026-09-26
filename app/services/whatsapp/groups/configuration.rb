module Whatsapp::Groups
  class Configuration
    class Conflict < StandardError; end

    def initialize(inbox, user)
      @inbox = inbox
      @user = user
    end

    def update_settings!(attributes, enabled: nil)
      settings = WhatsappGroupSetting.for(@inbox)
      HubDiagnostics::ChannelLock.with(@inbox.channel_id, exclusive: true) do
        settings.with_lock do
        check_version!(settings, attributes)
        settings.assign_attributes(attributes.except('lock_version'))
        settings.save!
        unless enabled.nil?
          raise ArgumentError, 'enabled must be boolean' unless [true, false].include?(enabled)
          channel = @inbox.channel
          channel.update!(provider_config: { ignore_group_messages: !enabled }) if channel.groups_enabled? != enabled
        end
        audit('group.settings_updated', inbox_id: @inbox.id, settings_revision: settings.lock_version)
        end
      end
      Whatsapp::Groups::BroadcastJob.perform_later(nil, nil, @inbox.id)
      settings
    end

    def update_group!(group, attributes, confirmed: false, publish: true)
      raise ActiveRecord::RecordNotFound unless group.inbox_id == @inbox.id

      old_users = group.allowed_users.ids
      Lock.with(group) do
        group.with_lock do
        check_version!(group, attributes)
        changes = attributes.slice(*WhatsappGroup::CONFIG_FIELDS)
        mode_change = changes.key?('treatment') && changes['treatment'] != group.treatment
        if mode_change
          raise Conflict, 'Confirme a troca de tratamento. O histórico não será convertido.' unless confirmed
          ensure_transition_safe!(group)
        end
        group.assign_attributes(changes)
        group.valid? || raise(ActiveRecord::RecordInvalid, group)
        invalid_assignment = group.conversations.where.not(status: :resolved).where.not(assignee_id: nil)
                                  .where.not(assignee_id: group.allowed_users.select(:id)).exists?
        raise Conflict, 'Reatribua os atendimentos em andamento antes de retirar o acesso do responsável.' if invalid_assignment

        group.policy_version += 1 if group.changed?
        group.mode_changed_at = Time.current if mode_change
        group.save!
        group.whatsapp_group_policy_changes.create!(version: group.policy_version, user: @user,
                                                     configuration: group.attributes.slice(*WhatsappGroup::CONFIG_FIELDS)) unless
          group.whatsapp_group_policy_changes.exists?(version: group.policy_version)
        end
      end
      audit('group.policy_updated', group_id: group.id, revision: group.policy_version)
      Whatsapp::Groups::BroadcastJob.perform_later(group.id, nil, nil, old_users) if publish
      group
    end

    def self.preview(group)
      {
        active_tickets: group.conversations.where.not(status: :resolved).count,
        pending_messages: group.whatsapp_group_messages.where(status: %w[queued sending uncertain]).count +
          Message.where(conversation_id: group.conversations.select(:id), message_type: :outgoing, source_id: [nil, '']).where.not(status: :failed).count
      }
    end

    private

    def ensure_transition_safe!(group)
      impact = self.class.preview(group)
      return if impact.values.all?(&:zero?)

      raise Conflict, 'Resolva os atendimentos e confirme/cancele os envios pendentes antes da troca de tratamento.'
    end

    def check_version!(record, attributes)
      value = attributes['lock_version']
      raise Conflict, 'Configuração alterada. Atualize a tela antes de salvar.' unless value.is_a?(Integer) && value == record.lock_version
    end

    def audit(event, metadata)
      HubDiagnostics::Recorder.emit(event, metadata.merge(component: 'whatsapp_groups', account_id: @inbox.account_id, user_id: @user.id))
    end
  end
end
