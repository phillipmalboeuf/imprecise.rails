require 'rails_helper'

RSpec.describe "Queries API", type: :request do
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

  describe "POST /queries" do
    context "when authenticated with API key" do
      it "creates a new query using API key via HTTP fetch" do
        expect(api_key).to be_present

        post queries_path,
          params: {
            query: "Is this spam?",
            project_id: project.id
          },
          headers: {
            "Authorization" => "Bearer #{api_key}"
          },
          as: :json

        expect(response).to have_http_status(:created)
        expect(response.content_type).to include("application/json")
        
        json_response = JSON.parse(response.body)
        expect(json_response["id"]).to be_present
        expect(json_response["query"]).to eq("Is this spam?")
        expect(json_response["project_id"]).to be_nil # Not included in response, but query should have it
        
        expect(Query.count).to eq(1)
        created_query = Query.last
        expect(created_query.project_id).to eq(project.id)
        expect(created_query.query).to eq("Is this spam?")
      end

      it "works with ApiKey authorization prefix" do
        post queries_path,
          params: {
            query: "Test with ApiKey prefix",
            project_id: project.id
          },
          headers: {
            "Authorization" => "ApiKey #{api_key}"
          },
          as: :json

        expect(response).to have_http_status(:created)
        expect(Query.count).to eq(1)
        expect(Query.last.query).to eq("Test with ApiKey prefix")
      end

      it "rejects invalid API key" do
        post queries_path,
          params: {
            query: "Test query",
            project_id: project.id
          },
          headers: {
            "Authorization" => "Bearer invalid-api-key-12345"
          },
          as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.content_type).to include("application/json")
        
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("unauthorized")
        expect(Query.count).to eq(0)
      end

      it "rejects request without Authorization header" do
        post queries_path,
          params: {
            query: "Test query",
            project_id: project.id
          },
          as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Query.count).to eq(0)
      end

      it "rejects request when project is not published" do
        draft_project = Project.create!(
          name: "Draft Project",
          slug: "draft-project-#{Time.current.to_i}",
          status: "draft",
          prompt_type: "is-it-spam",
          owner: user
        )
        draft_api_key = draft_project.decrypted_apikey

        post queries_path,
          params: {
            query: "Test query",
            project_id: draft_project.id
          },
          headers: {
            "Authorization" => "Bearer #{draft_api_key}"
          },
          as: :json

        expect(response).to have_http_status(:forbidden)
        expect(response.content_type).to include("application/json")
        
        json_response = JSON.parse(response.body)
        expect(json_response["error"]).to include("published")
        expect(Query.count).to eq(0)
      end
    end
  end
end
