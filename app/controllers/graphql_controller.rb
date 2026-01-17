# frozen_string_literal: true

class GraphqlController < ApplicationController
  allow_unauthenticated_access only: [:execute, :introspection]
  skip_before_action :verify_authenticity_token, only: [:execute, :introspection]

  # If accessing from outside this domain, nullify the session
  # This allows for outside API access while preventing CSRF attacks,
  # but you'll have to authenticate your user separately
  # protect_from_forgery with: :null_session

  def execute
    variables = prepare_variables(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]
    context = {
      # Query context goes here, for example:
      # current_user: current_user,
      api_key: extract_api_key,
    }
    result = ImpreciseAnalysisSchema.execute(query, variables: variables, context: context, operation_name: operation_name)
    render json: result
  rescue StandardError => e
    raise e unless Rails.env.development?
    handle_error_in_development(e)
  end

  def introspection
    # GET endpoint for schema introspection (useful for code generation)
    result = ImpreciseAnalysisSchema.execute(GraphQL::Introspection::INTROSPECTION_QUERY, context: {})
    render json: result
  rescue StandardError => e
    render json: { errors: [{ message: e.message, backtrace: e.backtrace }] }, status: 500
  end

  private

  # Extract API key from Authorization header
  def extract_api_key
    # Check Authorization header: "Bearer <apikey>" or "ApiKey <apikey>"
    auth_header = request.headers["Authorization"]
    return nil unless auth_header

    # Support both "Bearer" and "ApiKey" prefix
    matches = auth_header.match(/^(?:Bearer|ApiKey)\s+(.+)$/i)
    matches ? matches[1] : auth_header.strip
  end

  # Handle variables in form data, JSON body, or a blank value
  def prepare_variables(variables_param)
    case variables_param
    when String
      if variables_param.present?
        JSON.parse(variables_param) || {}
      else
        {}
      end
    when Hash
      variables_param
    when ActionController::Parameters
      variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{variables_param}"
    end
  end

  def handle_error_in_development(e)
    logger.error e.message
    logger.error e.backtrace.join("\n")

    render json: { errors: [{ message: e.message, backtrace: e.backtrace }], data: {} }, status: 500
  end
end
