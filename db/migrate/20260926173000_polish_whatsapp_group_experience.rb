class PolishWhatsappGroupExperience < ActiveRecord::Migration[7.0]
  def change
    add_column :whatsapp_groups, :profile_picture_checked_at, :datetime
    add_column :whatsapp_groups, :last_message_preview, :string, limit: 512
    add_column :whatsapp_groups, :last_sender_name, :string, limit: 256
    add_column :whatsapp_groups, :last_message_kind, :string, limit: 32

    add_column :whatsapp_group_preferences, :pinned, :boolean, null: false, default: false
    add_column :whatsapp_group_preferences, :pinned_at, :datetime

    add_index :whatsapp_group_preferences,
              [:user_id, :pinned, :pinned_at],
              name: 'index_group_preferences_on_pin'
  end
end
