require 'rails_helper'

RSpec.describe Project, type: :model do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123") }

  describe 'encrypted_apikey' do
    it 'generates a unique API key on creation' do
      project1 = Project.create!(
        name: "Test Project 1",
        slug: "test-project-1",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )
      project2 = Project.create!(
        name: "Test Project 2",
        slug: "test-project-2",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )

      expect(project1.encrypted_apikey).to be_present
      expect(project2.encrypted_apikey).to be_present
      expect(project1.encrypted_apikey).not_to eq(project2.encrypted_apikey)
    end

    it 'stores the API key as a SHA256 hash (one-way, cannot be decrypted)' do
      project = Project.create!(
        name: "Test Project",
        slug: "test-project",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )

      # SHA256 produces a 64-character hex string
      # The hashed API key should not look like a plain UUID (no hyphens)
      expect(project.encrypted_apikey).to match(/\A[0-9a-f]{64}\z/i)
      expect(project.encrypted_apikey).not_to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'can retrieve the API key immediately after creation (before reload)' do
      project = Project.create!(
        name: "Test Project",
        slug: "test-project",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )

      decrypted_apikey = project.decrypted_apikey
      expect(decrypted_apikey).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'cannot retrieve the API key after reload (one-way hash)' do
      project = Project.create!(
        name: "Test Project",
        slug: "test-project",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )

      # Reload from database - the raw API key is no longer in memory
      project.reload
      
      expect(project.decrypted_apikey).to be_nil
    end

    it 'ensures encrypted_apikey is unique in the database' do
      # This test verifies the database constraint
      project1 = Project.create!(
        name: "Test Project 1",
        slug: "test-project-1",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )

      # Try to create a project with the same encrypted_apikey (should fail due to unique constraint)
      project2 = Project.new(
        name: "Test Project 2",
        slug: "test-project-2",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user,
        encrypted_apikey: project1.encrypted_apikey
      )

      expect { project2.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'ensures decrypted API keys are unique' do
      # The raw API keys should be unique (before reload)
      project1 = Project.create!(
        name: "Test Project 1",
        slug: "test-project-1",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )
      project2 = Project.create!(
        name: "Test Project 2",
        slug: "test-project-2",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )

      expect(project1.decrypted_apikey).not_to eq(project2.decrypted_apikey)
    end

    it 'has an index on encrypted_apikey for uniqueness' do
      indexes = ActiveRecord::Base.connection.indexes('projects')
      apikey_index = indexes.find { |idx| idx.columns.include?('encrypted_apikey') }
      
      expect(apikey_index).to be_present
      expect(apikey_index.unique).to be true
    end

    it 'does not regenerate API key on update' do
      project = Project.create!(
        name: "Test Project",
        slug: "test-project",
        status: "draft",
        prompt_type: "is-it-spam",
        owner: user
      )

      original_apikey = project.encrypted_apikey
      project.update!(name: "Updated Project Name")
      
      expect(project.reload.encrypted_apikey).to eq(original_apikey)
    end
  end
end
