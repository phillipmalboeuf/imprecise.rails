require 'rails_helper'

RSpec.describe ProjectsController, type: :controller do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123") }
  let(:session) { user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1") }

  before do
    cookies.signed[:session_id] = session.id
    Current.session = session
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        project: {
          name: "Test Project",
          slug: "test-project-#{Time.current.to_i}",
          status: "draft",
          prompt_type: "is-it-spam"
        }
      }
    end

    context 'with valid parameters' do
      it 'creates a new project' do
        expect {
          post :create, params: valid_params
        }.to change(Project, :count).by(1)
      end

      it 'assigns a unique encrypted API key to the project' do
        post :create, params: valid_params
        
        project = Project.last
        expect(project.encrypted_apikey).to be_present
      end

      it 'displays the decrypted API key in the success flash message' do
        post :create, params: valid_params
        
        # The flash message should contain the API key (UUID format)
        # We can't retrieve it from the database after save since it's hashed
        expect(flash[:notice]).to include("API Key:")
        expect(flash[:notice]).to match(/API Key: [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i)
      end

      it 'redirects to projects index' do
        post :create, params: valid_params
        expect(response).to redirect_to(projects_path)
      end
    end

    context 'with invalid parameters' do
      it 'does not create a project' do
        expect {
          post :create, params: { project: { name: "" } }
        }.not_to change(Project, :count)
      end

      it 'does not assign an API key when project creation fails' do
        post :create, params: { project: { name: "" } }
        
        expect(Project.count).to eq(0)
      end
    end
  end
end
