# frozen_string_literal: true

module Types
  class ProjectType < Types::BaseObject
    description "A project for AI analysis"

    field :id, ID, null: false, description: "Unique identifier for the project"
    field :name, String, null: false, description: "Name of the project"
    field :slug, String, null: false, description: "URL-friendly identifier for the project"
    field :status, Types::ProjectStatusEnum, null: true, description: "Current status of the project"
    field :prompt_type, Types::PromptTypeEnum, null: false, description: "Type of analysis prompt"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the project was created"
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false, description: "When the project was last updated"
  end
end
