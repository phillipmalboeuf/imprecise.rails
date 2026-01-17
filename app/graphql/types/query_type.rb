# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    field :node, Types::NodeType, null: true, description: "Fetches an object given its ID." do
      argument :id, ID, required: true, description: "ID of the object."
    end

    def node(id:)
      context.schema.object_from_id(id, context)
    end

    field :nodes, [Types::NodeType, null: true], null: true, description: "Fetches a list of objects given a list of IDs." do
      argument :ids, [ID], required: true, description: "IDs of the objects."
    end

    def nodes(ids:)
      ids.map { |id| context.schema.object_from_id(id, context) }
    end

    # Add root-level fields here.
    # They will be entry points for queries on your schema.

    field :projects, [Types::ProjectType], null: false,
      description: "List all projects" do
      argument :user_id, ID, required: false, description: "Filter projects by owner user ID"
    end

    def projects(user_id: nil)
      projects = Project.all
      projects = projects.where(user_id: user_id) if user_id.present?
      projects.order(created_at: :desc)
    end

    field :project, Types::ProjectType, null: true,
      description: "Find a project by ID or slug" do
      argument :id, ID, required: false, description: "ID of the project"
      argument :slug, String, required: false, description: "Slug of the project"
    end

    def project(id: nil, slug: nil)
      if id.present?
        Project.find_by(id: id)
      elsif slug.present?
        Project.find_by(slug: slug)
      else
        raise GraphQL::ExecutionError, "Either id or slug must be provided"
      end
    end

    field :public_published_projects, [Types::ProjectType], null: false,
      description: "Public list of published projects for the first user (no owner information)"

    def public_published_projects
      Project.public_published_projects
    end
  end
end
