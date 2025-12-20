class Project < ApplicationRecord
  belongs_to :owner, class_name: "User", foreign_key: "user_id"

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[archived draft published] }
  validates :prompt_type, presence: true, inclusion: { in: %w[is-it-spam is-it-ai topics sentiment] }
end

