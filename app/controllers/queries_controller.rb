# typed: true
# frozen_string_literal: true

class QueriesController < ApplicationController
  allow_unauthenticated_access only: [:create]

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

    @query = Query.new(query_params)

    if @query.save
      ai_response = AiAnalysisService.new(@query).call
      @query.update(response: { content: ai_response }) if ai_response.present?

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

