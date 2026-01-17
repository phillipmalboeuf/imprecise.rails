# typed: true
# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :owner, class_name: "User", foreign_key: "user_id"
  has_many :queries, dependent: :destroy
  has_many :daily_usages, dependent: :nullify

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[archived draft published] }
  validates :prompt_type, presence: true, inclusion: { in: %w[is-it-spam is-it-ai topics sentiment] }
  validates :encrypted_apikey, presence: true, uniqueness: true

  before_validation :ensure_encrypted_apikey, on: :create

  def to_param
    slug
  end

  def published?
    status == "published"
  end

  def decrypted_apikey
    # The raw API key is only available immediately after creation, before reload
    # Once saved to the database, only the hash is stored and the original cannot be retrieved
    @_raw_apikey
  end

  def regenerate_apikey!
    apikey = SecureRandom.uuid
    # Store raw API key in memory temporarily so it can be displayed to the user
    @_raw_apikey = apikey
    # Hash the API key (one-way, cannot be decrypted)
    self.encrypted_apikey = Digest::SHA256.hexdigest(apikey)
    save!
  end

  def reload(*)
    @_raw_apikey = nil
    super
  end

  # Returns published projects for the first user (public access)
  def self.public_published_projects
    projects = User.order(:id).first&.projects || Project.none
    projects.where(status: "published").order(created_at: :asc)
  end

  private

    def ensure_encrypted_apikey
      return if self.encrypted_apikey.present?

      apikey = SecureRandom.uuid
      # Store raw API key in memory temporarily so it can be displayed to the user
      @_raw_apikey = apikey
      # Hash the API key (one-way, cannot be decrypted)
      self.encrypted_apikey = Digest::SHA256.hexdigest(apikey)
    end
end

