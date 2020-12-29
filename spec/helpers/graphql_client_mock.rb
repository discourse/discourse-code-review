# frozen_string_literal: true

class GraphQLClientMock
  module GitObjectType
    include GraphQL::Schema::Interface

    definition_methods do
      def resolve_type(object, context)
        CommitType
      end
    end
  end

  class UserType < GraphQL::Schema::Object
    field :login, String, null: false
    field :id, String, null: false

    def login
      "login"
    end

    def id
      "id"
    end
  end

  class GitActorType < GraphQL::Schema::Object
    field :user, UserType, null: true

    def user
      :user
    end
  end

  class CommitType < GraphQL::Schema::Object
    implements GitObjectType

    field :oid, String, null: false
    field :author, GitActorType, null: false
    field :committer, GitActorType, null: false

    def oid
      "oid"
    end

    def author
      :author
    end

    def committer
      :committer
    end
  end

  class RepositoryType < GraphQL::Schema::Object
    field :object, GitObjectType, null: true, resolver_method: :resolve_object do
      argument :expression, String, required: true
    end

    def resolve_object(expression:)
      :commit
    end
  end

  class QueryType < GraphQL::Schema::Object
    field :repository, RepositoryType, null: true do
      argument :owner, String, required: true
      argument :name, String, required: true
    end

    def repository(owner:, name:)
      :repo
    end
  end

  class GithubSchema < GraphQL::Schema
    query QueryType
    orphan_types CommitType
  end

  GraphQLError = GraphQLClient::GraphQLError
  PaginatedQuery = GraphQLClient::PaginatedQuery

  def execute(query)
    GithubSchema.execute(query).to_h.deep_symbolize_keys[:data]
  end

  def paginated_query(&blk)
    PaginatedQuery.new(self, &blk)
  end
end
