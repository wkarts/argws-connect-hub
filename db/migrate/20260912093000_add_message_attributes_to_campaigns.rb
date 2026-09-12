# frozen_string_literal: true

class AddMessageAttributesToCampaigns < ActiveRecord::Migration[7.0]
  def change
    add_column :campaigns, :message_attributes, :jsonb, default: {}, null: false
  end
end
