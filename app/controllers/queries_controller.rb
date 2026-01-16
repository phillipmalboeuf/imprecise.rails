# typed: true
# frozen_string_literal: true

class QueriesController < ApplicationController
  allow_unauthenticated_access only: [:create]

  MAX_MONTHLY_TOKENS = 10_000

  def create
    api_key = extract_api_key
    authenticated_via_api_key = false
    
    if api_key
      project = find_project_by_api_key(api_key)
      authenticated_via_api_key = true if project
    else
      resume_session # Ensure session is loaded for session-based auth
      project = find_project_by_user
    end

    unless project
      render json: { error: "Project not found or unauthorized." }, status: :unauthorized
      return
    end
    
    unless project.published?
      if authenticated_via_api_key
        render json: { error: "Project must be published to create queries." }, status: :forbidden
        return
      else
        redirect_to project_path(project), alert: "Project must be published to create queries."
        return
      end
    end

    # Check monthly token limit before creating the query
    @query = Query.new(query_params)
    @query.project = project
    
    # Estimate tokens for this query
    estimated_tokens = AiAnalysisService.new(@query).estimate_prompt_tokens
    
    # Get current monthly usage
    current_monthly_usage = DailyUsage.monthly_total(user: project.owner, project: project)
    
    # Check if adding this query would exceed the monthly limit (10,000 tokens)
    if current_monthly_usage + estimated_tokens > MAX_MONTHLY_TOKENS
      error_message = "Monthly token limit exceeded. Current usage: #{current_monthly_usage}, Estimated for this query: #{estimated_tokens}, Limit: #{MAX_MONTHLY_TOKENS}."
      if authenticated_via_api_key
        render json: { error: error_message }, status: :forbidden
        return
      else
        redirect_to project_path(project), alert: error_message
        return
      end
    end

    if @query.save
      ai_response = AiAnalysisService.new(@query).call
      @query.update(response: { content: ai_response }) if ai_response.present?

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

      # If authenticated via API key, return JSON response
      if authenticated_via_api_key
        render json: { 
          id: @query.id, 
          query: @query.query, 
          response: @query.response,
          created_at: @query.created_at
        }, status: :created
        return
      else
        redirect_to project_path(@query.project), notice: "Query created successfully!"
        return
      end
    else
      if authenticated_via_api_key
        render json: { errors: @query.errors.full_messages }, status: :unprocessable_entity
        return
      else
        redirect_to project_path(@query.project), alert: "Error: #{@query.errors.full_messages.join(', ')}"
        return
      end
    end
  end

  private

  def find_project_by_api_key(api_key)
    api_key_hash = Digest::SHA256.hexdigest(api_key)
    Project.find_by(encrypted_apikey: api_key_hash, id: params[:project_id])
  end

  def find_project_by_user
    return nil unless Current.user

    Current.user.projects.find_by(id: params[:project_id])
  end

  def extract_api_key
    # Check Authorization header: "Bearer <apikey>" or "ApiKey <apikey>"
    auth_header = request.headers["Authorization"]
    return nil unless auth_header

    # Support both "Bearer" and "ApiKey" prefix
    matches = auth_header.match(/^(?:Bearer|ApiKey)\s+(.+)$/i)
    matches ? matches[1] : auth_header.strip
  end

  def query_params
    params.permit(:query, :response, :project_id).tap do |permitted|
      # Handle JSON response field - it can come as a string (from form-data) or already parsed (from JSON)
      if params[:response].present?
        permitted[:response] = parse_response(params[:response])
      end
    end
  end

  def parse_response(response_param)
    case response_param
    when String
      JSON.parse(response_param)
    when Hash, Array
      response_param
    else
      response_param
    end
  rescue JSON::ParserError
    { error: "Invalid JSON in response field" }
  end
end

