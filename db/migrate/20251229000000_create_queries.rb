class CreateQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :queries do |t|
      t.text :query, null: false
      t.jsonb :response
      t.references :project, null: false, foreign_key: true

      t.timestamps
    end
  end
end

