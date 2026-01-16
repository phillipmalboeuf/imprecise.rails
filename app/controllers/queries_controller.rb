# typed: true
# frozen_string_literal: true

class QueriesController < ApplicationController
  def create
    project = Current.user.projects.find_by(id: params[:project_id])
    
    unless project
      redirect_to projects_path, alert: "Project not found."
      return
    end
    
    unless project.published?
      redirect_to project_path(project), alert: "Project must be published to create queries."
      return
    end

    @query = Query.new(query_params)

    if @query.save
      ai_response = AiAnalysisService.new(@query).call
      @query.update(response: { content: ai_response }) if ai_response.present?

      redirect_to project_path(@query.project), notice: "Query created successfully!"
    else
      redirect_to project_path(@query.project), alert: "Error: #{@query.errors.full_messages.join(', ')}"
    end
  end

  private

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

