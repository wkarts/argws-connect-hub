# frozen_string_literal: true

class Channels::Whatsapp::DeleteConnectApiInstanceJob < ApplicationJob
  queue_as :low
  retry_on HubDiagnostics::BindingBusy, wait: 5.seconds, attempts: 24

  def perform(instance_name)
    name = instance_name.to_s.strip
    return if name.blank?
    HubDiagnostics::InstanceLock.with(name) do
    # A cleanup queued before a rebind must not delete a currently linked session.
    if Channel::Whatsapp.where(provider: 'connectapi').where("provider_config ->> 'instance_name' = ?", name).exists?
      HubDiagnostics::Recorder.emit('cleanup.skipped', instance_name: name, reason: 'instance_is_linked')
      return
    end

    ConnectApi::Client.new.delete_instance(name)
    Rails.logger.info("[HUB Connect|API] deleted remote instance name=#{name}")
    end
  rescue ConnectApi::Error => e
    if e.status.to_i == 404
      Rails.logger.info("[HUB Connect|API] remote instance already absent name=#{name}")
      return
    end

    # Re-raise transient/server failures. Sidekiq keeps its normal retry policy,
    # without resolving ConnectApi::Error at class-load time during eager_load.
    raise
  end
end
