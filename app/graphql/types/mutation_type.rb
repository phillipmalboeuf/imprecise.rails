# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :create_query, mutation: Mutations::CreateQuery
  end
end
