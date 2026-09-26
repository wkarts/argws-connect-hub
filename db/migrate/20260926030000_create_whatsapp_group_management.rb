class CreateWhatsappGroupManagement < ActiveRecord::Migration[7.0]
  def change
    create_table :whatsapp_group_settings do |t|
      t.references :inbox, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.string :selection_mode, null: false, default: 'all'
      t.string :default_treatment, null: false, default: 'conversation'
      t.string :default_access_mode, null: false, default: 'inbox'
      t.jsonb :default_user_ids, null: false, default: []
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    create_table :whatsapp_groups do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.string :jid, null: false, limit: 80
      t.string :name, null: false, limit: 256
      t.boolean :selected, null: false, default: false
      t.string :treatment, null: false, default: 'conversation'
      t.string :access_mode, null: false, default: 'inbox'
      t.jsonb :allowed_user_ids, null: false, default: []
      t.integer :policy_version, null: false, default: 1
      t.datetime :mode_changed_at
      t.datetime :last_activity_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :whatsapp_groups, [:inbox_id, :jid], unique: true
    add_index :whatsapp_groups, [:account_id, :last_activity_at, :id], name: 'index_whatsapp_groups_on_activity'
    create_table :whatsapp_group_policy_changes do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.integer :version, null: false
      t.jsonb :configuration, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :whatsapp_group_policy_changes, [:whatsapp_group_id, :version], unique: true, name: 'index_group_policy_versions'
    create_table :whatsapp_group_messages do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :source_id
      t.string :client_id
      t.string :binding_token, null: false, limit: 64
      t.string :direction, null: false
      t.string :status, null: false, default: 'received'
      t.string :kind, null: false, default: 'text'
      t.string :sender_jid
      t.string :sender_name
      t.text :content
      t.string :reply_to_source_id
      t.string :external_error
      t.integer :policy_version, null: false
      t.boolean :historical, null: false, default: false
      t.datetime :sent_at, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :whatsapp_group_messages, [:whatsapp_group_id, :source_id], unique: true, where: 'source_id IS NOT NULL', name: 'index_group_messages_source'
    add_index :whatsapp_group_messages, [:whatsapp_group_id, :client_id], unique: true, where: 'client_id IS NOT NULL', name: 'index_group_messages_client'
    add_index :whatsapp_group_messages, [:whatsapp_group_id, :sent_at, :id], name: 'index_group_messages_timeline'
    add_index :whatsapp_group_messages, :source_id, where: "source_id IS NOT NULL", name: "idx_group_messages_provider_source"

    create_table :whatsapp_group_deliveries do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }
      t.string :source_id, null: false
      t.string :treatment, null: false
      t.integer :policy_version, null: false
      t.references :message, foreign_key: { on_delete: :nullify }
      t.references :whatsapp_group_message, foreign_key: { on_delete: :nullify }, index: { name: 'index_group_deliveries_managed_message' }
      t.timestamps
    end
    add_index :whatsapp_group_deliveries, [:whatsapp_group_id, :source_id], unique: true, name: 'index_group_deliveries_identity'
    create_table :whatsapp_group_pending_events do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }
      t.string :source_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :reason, null: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :whatsapp_group_pending_events, [:whatsapp_group_id, :source_id], unique: true, name: 'index_group_pending_identity'

    create_table :whatsapp_group_preferences do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :muted, null: false, default: false
      t.datetime :last_read_at
      t.timestamps
    end
    add_index :whatsapp_group_preferences, [:whatsapp_group_id, :user_id], unique: true, name: 'index_group_preferences_user'
    # Snapshot existing groups as Atendimento. No Conversation/Message callbacks,
    # no remote calls, no history migration and no disabled inbox is enabled.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO whatsapp_groups (account_id, inbox_id, jid, name, selected, treatment, access_mode, allowed_user_ids, policy_version, lock_version, created_at, updated_at)
          SELECT i.account_id, i.id, ci.source_id, LEFT(COALESCE(NULLIF(c.name, ''), ci.source_id), 256), TRUE, 'conversation', 'inbox', '[]'::jsonb, 1, 0, NOW(), NOW()
          FROM contact_inboxes ci JOIN inboxes i ON i.id = ci.inbox_id
          JOIN channel_whatsapp cw ON i.channel_type = 'Channel::Whatsapp' AND i.channel_id = cw.id
          JOIN contacts c ON c.id = ci.contact_id
          WHERE cw.provider = 'connectapi' AND ci.source_id ~ '^[0-9]+(-[0-9]+)?@g\\.us$'
          ON CONFLICT (inbox_id, jid) DO NOTHING
        SQL
      end
    end
  end
end
