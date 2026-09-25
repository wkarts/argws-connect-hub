class CreateWorkspaceApps < ActiveRecord::Migration[7.0]
  def change
    create_table :workspace_apps do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false, limit: 120
      t.text :url, null: false
      t.string :icon_name, null: false, default: 'globe'
      t.boolean :enabled, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string :launch_mode, null: false, default: 'embedded'
      t.string :auth_mode, null: false, default: 'session'
      t.text :login_url
      t.string :username_field, null: false, default: 'username'
      t.string :password_field, null: false, default: 'password'
      t.boolean :allow_saved_credentials, null: false, default: false
      t.boolean :allow_auto_login, null: false, default: false
      t.string :access_mode, null: false, default: 'everyone'
      t.jsonb :allowed_user_ids, null: false, default: []
      t.timestamps
    end
    add_index :workspace_apps, [:account_id, :position, :id], name: 'index_workspace_apps_on_account_order'

    create_table :workspace_app_credentials do |t|
      t.references :workspace_app, null: false, foreign_key: { on_delete: :cascade }
      t.references :account_user, null: false, foreign_key: { on_delete: :cascade }
      t.text :encrypted_credentials, null: false
      t.string :integration_revision, null: false
      t.boolean :auto_login, null: false, default: false
      t.timestamps
    end
    add_index :workspace_app_credentials, [:workspace_app_id, :account_user_id], unique: true,
              name: 'index_workspace_credentials_on_app_and_membership'
    # Deliberately no seeds: each company manages its own empty application catalog.
  end
end
