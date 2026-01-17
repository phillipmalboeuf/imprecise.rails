# frozen_string_literal: true

module Mutations
  class CreateQuery < BaseMutation
    description "Create a new query for AI analysis. API key required unless project is in public published projects list."

    argument :project_id, ID, required: true, description: "The project ID to create the query for"
    argument :query, String, required: true, description: "The query text to analyze"

    field :query, Types::QueryModelType, null: true, description: "The created query"
    field :errors, [String], null: false, description: "List of errors if the mutation failed"

    def resolve(project_id:, query:)
      # Extract API key from context
      api_key = context[:api_key]
      
      # Try to find project by API key if provided
      if api_key
        api_key_hash = Digest::SHA256.hexdigest(api_key)
        project = Project.find_by(encrypted_apikey: api_key_hash, id: project_id)
        
        unless project
          return {
            query: nil,
            errors: ["Project not found or unauthorized. Check your API key and project ID."]
          }
        end
      else
        # No API key provided - check if project is in public published projects
        public_projects = Project.public_published_projects
        project = public_projects.find_by(id: project_id)
        
        unless project
          return {
            query: nil,
            errors: ["Project not found or unauthorized. Either provide an API key or ensure the project is in the public published projects list."]
          }
        end
      end

      # Check if project is published
      unless project.published?
        return {
          query: nil,
          errors: ["Project must be published to create queries."]
        }
      end

      # Create query object
      new_query = Query.new(query: query, project: project)

      # Check if adding this query would exceed the monthly limit
      if error_message = new_query.monthly_token_limit_error_message
        return {
          query: nil,
          errors: [error_message]
        }
      end

      # Save the query
      unless new_query.save
        return {
          query: nil,
          errors: new_query.errors.full_messages
        }
      end

      # Run AI analysis
      new_query.run_ai_analysis!

      {
        query: new_query,
        errors: []
      }
    rescue StandardError => e
      {
        query: nil,
        errors: [e.message]
      }
    end
  end
end
