# frozen_string_literal: true
require 'digest'
module HubDiagnostics
  class ChannelLock
    def self.with(channel_id, exclusive: false)
      key = Digest::SHA256.digest("hub:channel-binding:#{Integer(channel_id)}").unpack1('q>')
      suffix = exclusive ? '' : '_shared'
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        acquired = connection.select_value("SELECT pg_try_advisory_lock#{suffix}(#{key})")
        raise BindingBusy, 'Channel binding is busy' unless acquired == true || acquired == 't'
        begin
          yield
        ensure
          connection.select_value("SELECT pg_advisory_unlock#{suffix}(#{key})")
        end
      end
    end
  end
end
