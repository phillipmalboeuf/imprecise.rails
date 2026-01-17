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

      # Estimate tokens for this query
      estimated_tokens = AiAnalysisService.new(new_query).estimate_prompt_tokens

      # Get current monthly usage
      current_monthly_usage = DailyUsage.monthly_total(user: project.owner, project: project)
      max_monthly_tokens = ApplicationController::MAX_MONTHLY_TOKENS

      # Check if adding this query would exceed the monthly limit
      if current_monthly_usage + estimated_tokens > max_monthly_tokens
        return {
          query: nil,
          errors: ["Monthly token limit exceeded. Current usage: #{current_monthly_usage}, Estimated for this query: #{estimated_tokens}, Limit: #{max_monthly_tokens}."]
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
      ai_response = AiAnalysisService.new(new_query).call
      if ai_response.present?
        # Store the response in a format that matches the controller's expectations
        response_data = if ai_response.is_a?(Hash)
          ai_response
        elsif ai_response.respond_to?(:to_h)
          ai_response.to_h
        else
          { content: ai_response }
        end
        new_query.update(response: response_data)
      end

      # Track daily usage if we have a valid AI response with usage information
      if ai_response.present? && !ai_response.is_a?(Hash) && ai_response.respond_to?(:usage)
        usage = ai_response.usage
        if usage && usage.respond_to?(:prompt_tokens)
          prompt_tokens = usage.prompt_tokens || 0
          if prompt_tokens > 0
            DailyUsage.increment_tokens!(
              day: Date.current,
              user: project.owner,
              project: project,
              tokens: prompt_tokens
            )
          end
        end
      end

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
