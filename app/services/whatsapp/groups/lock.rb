require 'digest'

module Whatsapp::Groups
  class Lock
    # Session locks do not roll back a durable "sending" marker when a worker
    # loses the provider response. Binding -> group is the common lock order.
    def self.with(group)
      HubDiagnostics::ChannelLock.with(group.inbox.channel_id) do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          key = Digest::SHA256.digest("hub:group:#{group.id}").unpack1('q>')
          acquired = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
          raise HubDiagnostics::BindingBusy, 'Group operation pending' unless acquired == true || acquired == 't'
          begin
            group.reload
            yield
          ensure
            connection.select_value("SELECT pg_advisory_unlock(#{key})")
          end
        end
      end
    end
  end
end
