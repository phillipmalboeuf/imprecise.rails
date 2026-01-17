# frozen_string_literal: true

module Types
  class QueryModelType < Types::BaseObject
    description "A query for AI analysis"

    field :id, ID, null: false, description: "Unique identifier for the query"
    field :query, String, null: false, description: "The query text to analyze"
    field :response, GraphQL::Types::JSON, null: true, description: "The AI analysis response"
    field :project_id, ID, null: false, description: "The project this query belongs to"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the query was created"
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the query was last updated"
  end
end
