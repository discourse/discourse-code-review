# frozen_string_literal: true

module DiscourseCodeReview
  CommitThread =
    TypedData::TypedStruct.new(
      github_id: String,
      actor: Actor,
      created_at: Time,
      commit_sha: String,
    )

  class Source::GithubPRQuerier
    def initialize(graphql_client)
      @graphql_client = graphql_client
    end

    def first_review_thread_comment_database_id(review_thread_id)
      response =
        graphql_client.execute(
          "
          query {
            node(id: #{review_thread_id.to_json}) {
              ... on PullRequestReviewThread {
                comments(first: 1) {
                  nodes {
                    databaseId
                  }
                }
              }
            }
          }
        ",
        )

      comment_id = response[:node][:comments][:nodes][0][:databaseId]
      raise "Expected Integer, but got #{comment_id.class}" unless Integer === comment_id

      comment_id
    end

    def first_review_thread_comment(review_thread)
      response =
        graphql_client.execute(
          "
          query {
            node(id: #{review_thread.github_id.to_json}) {
              ... on PullRequestReviewThread {
                comments(first: 1) {
                  nodes {
                    id,
                    createdAt,
                    author {
                      login
                    },
                    body,
                    diffHunk,
                    path
                  }
                }
              }
            }
          }
        ",
        )

      comment = response[:node][:comments][:nodes][0]

      event_info =
        PullRequestEventInfo.new(
          actor: Actor.new(github_login: comment[:author][:login]),
          github_id: comment[:id],
          created_at: Time.parse(comment[:createdAt]),
        )

      diff_hunk = comment[:diffHunk]
      path = comment[:path]
      context =
        if diff_hunk.present? && path.present?
          CommentContext.new(diff_hunk: diff_hunk, path: path)
        end

      event =
        PullRequestEvent.create(
          :review_thread_started,
          body: comment[:body],
          context: context,
          thread: CommentThread.new(github_id: review_thread.github_id),
        )

      [event_info, event]
    end

    def subsequent_review_thread_comments(review_thread)
      comments =
        graphql_client.paginated_query do |execute, cursor|
          query =
            "
            query {
              node(id: #{review_thread.github_id.to_json}) {
                ... on PullRequestReviewThread {
                  comments(first: 100, after: #{cursor.to_json}) {
                    nodes {
                      id,
                      createdAt,
                      author {
                        login
                      },
                      body
                    },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            }
          "
          response = execute.call(query)
          data = response[:node][:comments]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage],
          }
        end

      comments
        .lazy
        .each_cons
        .map do |previous, comment|
          event_info =
            PullRequestEventInfo.new(
              actor: Actor.new(github_login: comment[:author][:login]),
              github_id: comment[:id],
              created_at: Time.parse(comment[:createdAt]),
            )

          event =
            PullRequestEvent.create(
              :review_comment,
              body: comment[:body],
              reply_to_github_id: previous[:id],
              thread: CommentThread.new(github_id: review_thread.github_id),
            )

          [event_info, event]
        end
        .eager
    end

    def review_threads(pr)
      events =
        graphql_client.paginated_query do |execute, cursor|
          query =
            "
            query {
              repository(owner: #{pr.owner.to_json}, name: #{pr.name.to_json}) {
                pullRequest(number: #{pr.issue_number.to_json}) {
                  reviewThreads(first: 100) {
                    nodes {
                      id
                    },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            }
          "
          response = execute.call(query)
          data = response[:repository][:pullRequest][:reviewThreads]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage],
          }
        end

      events.lazy.map { |event| CommentThread.new(github_id: event[:id]) }.eager
    end

    def commit_threads(pr)
      events =
        graphql_client.paginated_query do |execute, cursor|
          query =
            "
            query {
              repository(owner: #{pr.owner.to_json}, name: #{pr.name.to_json}) {
                pullRequest(number: #{pr.issue_number.to_json}) {
                  timelineItems(first: 100, itemTypes: [PULL_REQUEST_COMMIT_COMMENT_THREAD], after: #{cursor.to_json}) {
                    nodes {
                      ... on PullRequestCommitCommentThread {
                        id,
                        commit {
                          oid
                        },
                        comments(first: 1) {
                          nodes {
                            author {
                              login
                            },
                            createdAt,
                          }
                        }
                      }
                    },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            }
          "
          response = execute.call(query)
          data = response[:repository][:pullRequest][:timelineItems]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage],
          }
        end

      events
        .lazy
        .map do |event|
          first_comment = event[:comments][:nodes][0]

          CommitThread.new(
            github_id: event[:id],
            actor: Actor.new(github_login: first_comment[:author][:login]),
            commit_sha: event[:commit][:oid],
            created_at: Time.parse(first_comment[:createdAt]),
          )
        end
        .eager
    end

    def is_merged_into_default?(pr)
      response =
        graphql_client.execute(
          "
          query {
            repository(owner: #{pr.owner.to_json}, name: #{pr.name.to_json}) {
              pullRequest(number: #{pr.issue_number.to_json}) {
                baseRefName,
                merged,
              },
              defaultBranchRef {
                name,
              },
            }
          }
        ",
        )

      default_branch = response[:repository][:defaultBranchRef][:name]
      pr_response = response[:repository][:pullRequest]

      pr_response[:baseRefName] == default_branch && pr_response[:merged]
    end

    def merged_by(pr)
      response =
        graphql_client.execute(
          "
          query {
            repository(owner: #{pr.owner.to_json}, name: #{pr.name.to_json}) {
              pullRequest(number: #{pr.issue_number.to_json}) {
                mergedBy {
                  login
                }
              }
            }
          }
        ",
        )

      merged_by = response[:repository][:pullRequest][:mergedBy]

      Actor.new(github_login: merged_by[:login]) if merged_by
    end

    def approvers(pr)
      item_types = ["PULL_REQUEST_REVIEW"]

      events =
        graphql_client.paginated_query do |execute, cursor|
          query =
            "
            query {
              repository(owner: #{pr.owner.to_json}, name: #{pr.name.to_json}) {
                pullRequest(number: #{pr.issue_number.to_json}) {
                  timelineItems(first: 100, itemTypes: [#{item_types.join(",")}], after: #{cursor.to_json}) {
                    nodes {
                      ... on PullRequestReview {
                        state,
                        author {
                          login
                        },
                      }
                    },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            }
          "
          response = execute.call(query)
          data = response[:repository][:pullRequest][:timelineItems]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage],
          }
        end

      events
        .select { |event| event[:state] == "APPROVED" }
        .map { |event| Actor.new(github_login: event[:author][:login]) }
    end

    def timeline(pr)
      item_types = %w[
        CLOSED_EVENT
        ISSUE_COMMENT
        MERGED_EVENT
        PULL_REQUEST_REVIEW
        RENAMED_TITLE_EVENT
        REOPENED_EVENT
      ]

      events =
        graphql_client.paginated_query do |execute, cursor|
          query =
            "
            query {
              repository(owner: #{pr.owner.to_json}, name: #{pr.name.to_json}) {
                pullRequest(number: #{pr.issue_number.to_json}) {
                  timelineItems(first: 100, itemTypes: [#{item_types.join(",")}], after: #{cursor.to_json}) {
                    nodes {
                      ... on ClosedEvent {
                        __typename,
                        id,
                        createdAt,
                        actor {
                          login
                        }
                      },
                      ... on IssueComment {
                        __typename,
                        id,
                        createdAt,
                        actor: author {
                          login
                        },
                        body
                      },
                      ... on MergedEvent {
                        __typename,
                        id,
                        createdAt,
                        actor {
                          login
                        }
                      },
                      ... on PullRequestReview {
                        __typename,
                        id,
                        createdAt,
                        actor: author {
                          login
                        },
                        body
                      }
                      ... on RenamedTitleEvent {
                        __typename,
                        id,
                        createdAt,
                        actor {
                          login
                        },
                        previousTitle,
                        currentTitle
                      },
                      ... on ReopenedEvent {
                        __typename,
                        id,
                        createdAt,
                        actor {
                          login
                        }
                      }
                    },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            }
          "
          response = execute.call(query)
          data = response[:repository][:pullRequest][:timelineItems]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage],
          }
        end

      events
        .lazy
        .filter_map do |event|
          event_info =
            PullRequestEventInfo.new(
              github_id: event[:id],
              actor: Actor.new(github_login: event[:actor][:login]),
              created_at: Time.parse(event[:createdAt]),
            )

          event =
            case event[:__typename]
            when "ClosedEvent"
              PullRequestEvent.create(:closed)
            when "PullRequestReview"
              PullRequestEvent.create(:issue_comment, body: event[:body]) if event[:body].present?
            when "IssueComment"
              PullRequestEvent.create(:issue_comment, body: event[:body])
            when "MergedEvent"
              PullRequestEvent.create(:merged)
            when "RenamedTitleEvent"
              PullRequestEvent.create(
                :renamed_title,
                previous_title: event[:previousTitle],
                new_title: event[:currentTitle],
              )
            when "ReopenedEvent"
              PullRequestEvent.create(:reopened)
            else
              raise "Unexpected typename"
            end

          [event_info, event] unless event.nil?
        end
        .eager
    end

    def pull_request_data(pr)
      response =
        graphql_client.execute(
          "
          query {
            repository(owner: #{pr.owner.to_json}, name: #{pr.name.to_json}) {
              pullRequest(number: #{pr.issue_number.to_json}) {
                id,
                author {
                  login
                },
                body,
                title,
                createdAt
              }
            }
          }
        ",
        )

      data = response[:repository][:pullRequest]
      PullRequestData.new(
        author: Actor.new(github_login: data[:author][:login]),
        body: data[:body],
        title: data[:title],
        created_at: Time.parse(data[:createdAt]),
        github_id: data[:id],
      )
    end

    def pull_requests(owner, name)
      prs =
        graphql_client.paginated_query do |execute, cursor|
          response =
            execute.call(
              "
              query {
                repository(owner: #{owner.to_json}, name: #{name.to_json}) {
                  pullRequests(first: 100, orderBy: { direction: DESC, field: CREATED_AT }, after: #{cursor.to_json}) {
                    nodes { number },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            ",
            )
          data = response[:repository][:pullRequests]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage],
          }
        end

      prs
        .lazy
        .map { |pr| PullRequest.new(owner: owner, name: name, issue_number: pr[:number]) }
        .eager
    end

    def associated_pull_requests(owner, name, commit_sha)
      uri = "https://github.com/#{owner}/#{name}/commit/#{commit_sha}"

      prs =
        graphql_client.paginated_query do |execute, cursor|
          response =
            execute.call(
              "
              query {
                resource(url: #{uri.to_json}) {
                  ... on Commit {
                    associatedPullRequests(first: 100, after: #{cursor.to_json}) {
                      nodes { number, repository { nameWithOwner } },
                      pageInfo { endCursor, hasNextPage }
                    }
                  }
                }
              }
            ",
            )
          data = response[:resource][:associatedPullRequests]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage],
          }
        end

      prs
        .lazy
        .map do |pr|
          owner, name = pr[:repository][:nameWithOwner].split("/")

          PullRequest.new(owner: owner, name: name, issue_number: pr[:number])
        end
        .eager
    end

    private

    attr_reader :graphql_client
  end
end
