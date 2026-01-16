class CreateDailyUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_usages do |t|
      t.date :day, null: false
      t.integer :token_used, default: 0, null: false
      t.references :user, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true, index: true

      t.timestamps
    end

    add_index :daily_usages, [:day, :user_id, :project_id], unique: true, name: "index_daily_usages_on_day_user_and_project"
  end
end
