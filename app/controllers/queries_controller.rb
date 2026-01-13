class QueriesController < ApplicationController
  # Skip CSRF token verification for API requests (both JSON and multipart/form-data)
  skip_before_action :verify_authenticity_token

  def create
    @query = Query.new(query_params)

    if @query.save
      render json: @query.as_json(include: :project), status: :created
    else
      render json: { errors: @query.errors.full_messages }, status: :unprocessable_entity
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

