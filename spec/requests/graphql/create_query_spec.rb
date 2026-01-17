# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "GraphQL CreateQuery Mutation", type: :request do
  let(:user) { User.create!(email_address: "test@example.com", password: "password123") }
  let(:project) do
    Project.create!(
      name: "Test Project",
      slug: "test-project-#{Time.current.to_i}",
      status: "published",
      prompt_type: "is-it-spam",
      owner: user
    )
  end
  let(:api_key) { project.decrypted_apikey }
  let(:mutation) do
    <<~GRAPHQL
      mutation CreateQuery($input: CreateQueryInput!) {
        createQuery(input: $input) {
          query {
            id
            query
            response
            projectId
            createdAt
          }
          errors
        }
      }
    GRAPHQL
  end
  let(:variables) { { input: { projectId: project.id.to_s, query: "Is this spam?" } } }

  describe "POST /graphql" do
    context "with valid API key in Authorization header" do
      it "creates a query successfully" do
        post "/graphql",
          params: {
            query: mutation,
            variables: variables.to_json
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{api_key}"
          }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")

        result = JSON.parse(response.body)
        expect(result["errors"]).to be_nil
        expect(result["data"]["createQuery"]["errors"]).to be_empty
        expect(result["data"]["createQuery"]["query"]).to be_present
        expect(result["data"]["createQuery"]["query"]["query"]).to eq("Is this spam?")
        expect(result["data"]["createQuery"]["query"]["projectId"]).to eq(project.id.to_s)

        expect(Query.count).to eq(1)
        created_query = Query.last
        expect(created_query.query).to eq("Is this spam?")
        expect(created_query.project_id).to eq(project.id)
        
        # Verify answer field is populated if AI response contains choices
        if created_query.answer.present?
          expect(created_query.answer).to be_an(Array)
          expect(created_query.answer.all? { |item| item.is_a?(String) }).to be true
        end
      end

      it "works with ApiKey prefix" do
        post "/graphql",
          params: {
            query: mutation,
            variables: variables.to_json
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "ApiKey #{api_key}"
          }

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["data"]["createQuery"]["errors"]).to be_empty
        expect(result["data"]["createQuery"]["query"]).to be_present
        expect(Query.count).to eq(1)
      end
    end

    context "without API key" do
      context "when project is in public published projects" do
        before do
          # Ensure project belongs to the first user (public published projects)
          first_user = User.order(:id).first || user
          project.update!(owner: first_user)
        end

        it "creates a query successfully" do
          post "/graphql",
            params: {
              query: mutation,
              variables: variables.to_json
            }.to_json,
            headers: {
              "Content-Type" => "application/json"
            }

          expect(response).to have_http_status(:ok)
          result = JSON.parse(response.body)
          expect(result["errors"]).to be_nil
          expect(result["data"]["createQuery"]["errors"]).to be_empty
          expect(result["data"]["createQuery"]["query"]).to be_present
          expect(result["data"]["createQuery"]["query"]["query"]).to eq("Is this spam?")
          expect(Query.count).to eq(1)
        end
      end

      context "when project is NOT in public published projects" do
        before do
          # Create first user (this will be User.order(:id).first)
          @first_user = User.order(:id).first || User.create!(email_address: "first@example.com", password: "password123")
          # Ensure first user has a published project so public_published_projects returns something
          unless @first_user.projects.where(status: "published").any?
            Project.create!(
              name: "First User Project",
              slug: "first-user-project-#{Time.current.to_i}",
              status: "published",
              prompt_type: "is-it-ai",
              owner: @first_user
            )
          end
          # Create second user (NOT the first user)
          @second_user = User.create!(email_address: "second@example.com", password: "password123")
          # Create project owned by second_user (NOT in public published projects)
          @private_project = Project.create!(
            name: "Private Project",
            slug: "private-project-#{Time.current.to_i}",
            status: "published",
            prompt_type: "is-it-spam",
            owner: @second_user
          )
          # Verify project is NOT in public published projects
          public_project_ids = Project.public_published_projects.pluck(:id)
          expect(public_project_ids).not_to include(@private_project.id)
        end

        it "returns an error" do
          post "/graphql",
            params: {
              query: mutation,
              variables: { input: { projectId: @private_project.id.to_s, query: "Is this spam?" } }.to_json
            }.to_json,
            headers: {
              "Content-Type" => "application/json"
            }

          expect(response).to have_http_status(:ok)
          result = JSON.parse(response.body)
          expect(result["data"]["createQuery"]["query"]).to be_nil
          expect(result["data"]["createQuery"]["errors"]).to be_present
          expect(result["data"]["createQuery"]["errors"]).to include(
            match(/Project not found or unauthorized.*public published projects/i)
          )
          expect(Query.count).to eq(0)
        end
      end
    end

    context "with invalid API key" do
      it "returns an error" do
        post "/graphql",
          params: {
            query: mutation,
            variables: variables.to_json
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer invalid-api-key"
          }

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["data"]["createQuery"]["query"]).to be_nil
        expect(result["data"]["createQuery"]["errors"]).to include(
          "Project not found or unauthorized. Check your API key and project ID."
        )
        expect(Query.count).to eq(0)
      end
    end

    context "with unpublished project" do
      let(:unpublished_project) do
        Project.create!(
          name: "Draft Project",
          slug: "draft-project-#{Time.current.to_i}",
          status: "draft",
          prompt_type: "is-it-spam",
          owner: user
        )
      end
      let(:api_key) { unpublished_project.decrypted_apikey }
      let(:variables) { { input: { projectId: unpublished_project.id.to_s, query: "Is this spam?" } } }

      it "returns an error" do
        post "/graphql",
          params: {
            query: mutation,
            variables: variables.to_json
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{api_key}"
          }

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["data"]["createQuery"]["query"]).to be_nil
        expect(result["data"]["createQuery"]["errors"]).to include(
          "Project must be published to create queries."
        )
        expect(Query.count).to eq(0)
      end
    end

    context "with monthly token limit exceeded" do
      before do
        DailyUsage.create!(
          user: user,
          project: project,
          day: Date.current,
          token_used: ApplicationController::MAX_MONTHLY_TOKENS
        )
      end

      it "returns an error" do
        post "/graphql",
          params: {
            query: mutation,
            variables: variables.to_json
          }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "Authorization" => "Bearer #{api_key}"
          }

        expect(response).to have_http_status(:ok)
        result = JSON.parse(response.body)
        expect(result["data"]["createQuery"]["query"]).to be_nil
        expect(result["data"]["createQuery"]["errors"]).to include(
          match(/Monthly token limit exceeded/)
        )
        expect(Query.count).to eq(0)
      end
    end
  end
end
