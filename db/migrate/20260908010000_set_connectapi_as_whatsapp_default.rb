# frozen_string_literal: true

class SetConnectapiAsWhatsappDefault < ActiveRecord::Migration[7.0]
  def up
    change_column_default :channel_whatsapp, :provider, from: 'default', to: 'connectapi'
  end

  def down
    change_column_default :channel_whatsapp, :provider, from: 'connectapi', to: 'default'
  end
end
