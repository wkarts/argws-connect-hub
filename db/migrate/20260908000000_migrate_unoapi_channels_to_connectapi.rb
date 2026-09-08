# frozen_string_literal: true

class MigrateUnoapiChannelsToConnectapi < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL.squish
      UPDATE channel_whatsapp
      SET provider = 'connectapi'
      WHERE provider = 'unoapi'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE channel_whatsapp
      SET provider = 'unoapi'
      WHERE provider = 'connectapi'
    SQL
  end
end
