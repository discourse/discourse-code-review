# frozen_string_literal: true

module DiscourseCodeReview
  ActorWithId =
    TypedData::TypedStruct.new(
      login: String,
      id: TypedData::OrNil[Integer],
    )

  CommitAuthorInfo =
    TypedData::TypedStruct.new(
      oid: String,
      author: TypedData::OrNil[ActorWithId],
      committer: TypedData::OrNil[ActorWithId],
    )

  class Source::CommitQuerier
    def initialize(graphql_client)
      @graphql_client = graphql_client
    end

    def commits_authors(owner, name, refs)
      query = "
        query {
          repository(owner: #{owner.to_json}, name: #{name.to_json}) {
            #{refs.each_with_index.map do |ref, i|
              "
            commit_#{i}: object(expression: #{ref.to_json}) {
              ... on Commit {
                oid,
                author {
                  user {
                    login,
                    id,
                  }
                },
                committer {
                  user {
                    login,
                    id,
                  }
                },
              }
            },
            ".lstrip
            end.join.rstrip}
          }
        }
      "

      response = @graphql_client.execute(query)[:repository]

      commits =
        refs.each_with_index.map do |ref, i|
          commit = response[:"commit_#{i}"]
          info =
            CommitAuthorInfo.new(
              oid: commit[:oid],
              author: build_actor_with_id(commit[:author][:user]),
              committer: build_actor_with_id(commit[:committer][:user]),
            )

          [ref, info]
        end

      Hash[commits]
    end

    private

    def build_actor_with_id(actor)
      if actor
        ActorWithId.new(
          login: actor[:login],
          id: decode_user_id(actor[:id]),
        )
      end
    end

    # TODO:
    #   The ids that github provides are supposed to be treated as opaque.
    #
    #   Unfortunately, we store raw github ids in the DB since they used to be
    #   exposed in the REST API. This is an interim measure until we switch to
    #   using the string ids.
    def decode_user_id(id)
      if id
        if m = /^04:User(\d+)$/.match(Base64.decode64(id))
          m[1].to_i
        end
      end
    end
  end
end
