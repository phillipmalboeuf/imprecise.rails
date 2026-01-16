class AddEncryptedApikeyToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :encrypted_apikey, :text
    add_index :projects, :encrypted_apikey, unique: true
  end
end
