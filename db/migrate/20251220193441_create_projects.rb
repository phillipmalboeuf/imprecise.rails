class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :user, null: true, foreign_key: true
      t.string :status
      t.string :name, null: false
      t.string :slug, null: false
      t.string :prompt_type, null: false

      t.timestamps
    end

    add_index :projects, :slug, unique: true
  end
end

