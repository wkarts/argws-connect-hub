class IndexWhatsappGroupInboxes < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    add_index :contact_inboxes, [:inbox_id, :id],
              where: "source_id ~ '^[0-9]+(-[0-9]+)?@g\\.us$'",
              name: 'index_contact_inboxes_whatsapp_groups', algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :contact_inboxes, name: 'index_contact_inboxes_whatsapp_groups', algorithm: :concurrently, if_exists: true
  end
end
