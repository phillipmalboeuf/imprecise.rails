# frozen_string_literal: true

class AddAnswerToQueries < ActiveRecord::Migration[8.1]
  def change
    add_column :queries, :answer, :text, array: true, default: []
  end
end
