require 'rails_helper'

RSpec.describe QueriesController, type: :controller do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123") }
  let(:session) { user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1") }

  before do
    cookies.signed[:session_id] = session.id
    Current.session = session
  end

  describe 'POST #create' do
    context 'when project is published' do
      let(:project) do
        Project.create!(
          name: "Published Project",
          slug: "published-project-#{Time.current.to_i}",
          status: "published",
          prompt_type: "is-it-spam",
          owner: user
        )
      end

      it 'allows query creation' do
        post :create, params: {
          query: "Test query",
          project_id: project.id
        }

        expect(response).to redirect_to(project_path(project))
        expect(flash[:notice]).to eq("Query created successfully!")
        expect(Query.count).to eq(1)
      end
    end

    context 'when project is draft' do
      let(:project) do
        Project.create!(
          name: "Draft Project",
          slug: "draft-project-#{Time.current.to_i}",
          status: "draft",
          prompt_type: "is-it-spam",
          owner: user
        )
      end

      it 'prevents query creation' do
        post :create, params: {
          query: "Test query",
          project_id: project.id
        }

        expect(response).to redirect_to(project_path(project))
        expect(flash[:alert]).to include("Project must be published")
        expect(Query.count).to eq(0)
      end
    end

    context 'when project is archived' do
      let(:project) do
        Project.create!(
          name: "Archived Project",
          slug: "archived-project-#{Time.current.to_i}",
          status: "archived",
          prompt_type: "is-it-spam",
          owner: user
        )
      end

      it 'prevents query creation' do
        post :create, params: {
          query: "Test query",
          project_id: project.id
        }

        expect(response).to redirect_to(project_path(project))
        expect(flash[:alert]).to include("Project must be published")
        expect(Query.count).to eq(0)
      end
    end

    context 'when authenticated with API key' do
      let(:user) { User.create!(email_address: "test@example.com", password: "password123") }
      let(:project) do
        Project.create!(
          name: "Published Project",
          slug: "published-project-#{Time.current.to_i}",
          status: "published",
          prompt_type: "is-it-spam",
          owner: user
        )
      end
      let(:api_key) { project.decrypted_apikey }

      before do
        # Don't set session cookies - we're testing API key auth
        cookies.signed[:session_id] = nil
        Current.session = nil
      end

      it 'creates a query using API key authentication via HTTP' do
        expect(api_key).to be_present

        request.env['HTTP_AUTHORIZATION'] = "Bearer #{api_key}"
        post :create, params: {
          query: "Test query via API key",
          project_id: project.id
        }

        expect(response.status).to eq(201)
        expect(response.content_type).to include("application/json")
        
        json_response = JSON.parse(response.body)
        expect(json_response["id"]).to be_present
        expect(json_response["query"]).to eq("Test query via API key")
        expect(Query.count).to eq(1)
        
        created_query = Query.last
        expect(created_query.project_id).to eq(project.id)
        expect(created_query.query).to eq("Test query via API key")
      end

      it 'rejects invalid API key' do
        request.env['HTTP_AUTHORIZATION'] = "Bearer invalid-api-key"
        post :create, params: {
          query: "Test query",
          project_id: project.id
        }

        expect(response.status).to eq(401)
        expect(response.content_type).to include("application/json")
        
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("unauthorized")
        expect(Query.count).to eq(0)
      end

      it 'rejects request without API key' do
        post :create,
          params: {
            query: "Test query",
            project_id: project.id
          }

        expect(response.status).to eq(401)
        expect(response.content_type).to include("application/json")
        
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("unauthorized")
        expect(Query.count).to eq(0)
      end
    end
  end
end
