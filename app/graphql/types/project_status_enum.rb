# frozen_string_literal: true

module Types
  class ProjectStatusEnum < Types::BaseEnum
    description "Status of a project"
    value "ARCHIVED", value: "archived", description: "Project is archived"
    value "DRAFT", value: "draft", description: "Project is in draft"
    value "PUBLISHED", value: "published", description: "Project is published"
  end
end
