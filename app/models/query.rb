# typed: true
# frozen_string_literal: true

class Query < ApplicationRecord
  belongs_to :project

  validates :query, presence: true
end

