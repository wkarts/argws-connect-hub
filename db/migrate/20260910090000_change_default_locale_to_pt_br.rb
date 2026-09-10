class ChangeDefaultLocaleToPtBr < ActiveRecord::Migration[7.0]
  def change
    change_column_default :accounts, :locale, from: 0, to: 16
    change_column_default :email_templates, :locale, from: 0, to: 16
  end
end
