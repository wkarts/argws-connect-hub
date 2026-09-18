# frozen_string_literal: true
require 'digest'
class HubDiagnostics::InstanceLock
  def self.with(name)
    key = Digest::SHA256.digest("hub:instance-operation:#{name}").unpack1('q>')
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      acquired = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
      raise HubDiagnostics::BindingBusy, 'Instance operation pending' unless acquired == true || acquired == 't'
      begin
        yield
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{key})")
      end
    end
  end
end
