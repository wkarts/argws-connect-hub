class AddDateOfBirthToContacts < ActiveRecord::Migration[7.0]
  def up
    return if column_exists?(:contacts, :date_of_birth)

    add_column :contacts, :date_of_birth, :date
  end

  def down
    return unless column_exists?(:contacts, :date_of_birth)

    remove_column :contacts, :date_of_birth
  end
end
