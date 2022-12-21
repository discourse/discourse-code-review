# frozen_string_literal: true

module DiscourseCodeReview
  PullRequest =
    TypedData::TypedStruct.new(
      owner: String,
      name: String,
      issue_number: Integer
    )

  CommentThread =
    TypedData::TypedStruct.new(
      github_id: String
    )

  Actor =
    TypedData::TypedStruct.new(
      github_login: String
    )

  PullRequestEventInfo =
    TypedData::TypedStruct.new(
      github_id: String,
      created_at: Time,
      actor: Actor
    )

  CommentContext =
    TypedData::TypedStruct.new(
      path: String,
      diff_hunk: String
    )

  PullRequestEvent =
    TypedData::TypedTaggedUnion.new(
      closed: {},

      commit_thread_started: {
        commit_sha: String
      },

      issue_comment: {
        body: String
      },

      merged: {},

      review_thread_started: {
        thread: CommentThread,
        body: String,
        context: TypedData::OrNil[CommentContext],
      },

      review_comment: {
        thread: CommentThread,
        body: String,
        reply_to_github_id: String
      },

      renamed_title: {
        previous_title: String,
        new_title: String
      },

      reopened: {}
    )

  PullRequestData =
    TypedData::TypedStruct.new(
      title: String,
      body: String,
      github_id: String,
      created_at: Time,
      author: Actor
    )

  class Source::GithubPRService
    class EventStream
      include Enumerable

      def initialize(pr_querier, pr)
        @pr_querier = pr_querier
        @pr = pr
      end

      def each(&blk)
        enumerables = [
          pr_querier.timeline(pr)
        ]

        enumerables.push(
          pr_querier
            .commit_threads(pr)
            .group_by(&:commit_sha)
            .values
            .map { |x| x.min_by(&:created_at) }
            .sort_by(&:created_at)
            .map { |x|
              event_info =
                PullRequestEventInfo.new(
                  actor: x.actor,
                  github_id: x.github_id,
                  created_at: x.created_at
                )

              event =
                PullRequestEvent.create(
                  :commit_thread_started,
                  commit_sha: x.commit_sha
                )

              [event_info, event]
            }
        )

        review_threads =
          pr_querier
            .review_threads(pr)
            .to_a

        enumerables.concat(
          review_threads.flat_map { |thread|
            first = [pr_querier.first_review_thread_comment(thread)]
            rest = pr_querier.subsequent_review_thread_comments(thread)

            [first, rest]
          }
        )

        Enumerators::FlattenMerge
          .new(enumerables) { |a, b|
            a[0].created_at < b[0].created_at
          }
          .each(&blk)
      end

      private

      attr_reader :pr_querier
      attr_reader :pr
    end

    def initialize(client, pr_querier)
      @client = client
      @pr_querier = pr_querier
    end

    def pull_requests(repo_name)
      owner, name = repo_name.split('/', 2)

      pr_querier.pull_requests(owner, name)
    end

    def associated_pull_requests(repo_name, commit_sha, include_external: false)
      owner, name = repo_name.split('/', 2)

      prs = pr_querier.associated_pull_requests(owner, name, commit_sha)

      unless include_external
        return prs.reject { |pr| external?(pr) }
      end

      prs
    end

    def pull_request_data(pr)
      pr_querier.pull_request_data(pr)
    end

    def pull_request_events(pr)
      EventStream.new(pr_querier, pr)
    end

    def create_issue_comment(repo_name, issue_number, body)
      client.add_comment(repo_name, issue_number, body)
    end

    def create_review_comment(repo_name, issue_number, body, thread_id)
      first_comment_id =
        pr_querier.first_review_thread_comment_database_id(thread_id)

      client.create_pull_request_comment_reply(
        repo_name,
        issue_number,
        body,
        first_comment_id
      )
    end

    def merge_info(pr)
      approvers =
        if pr_querier.is_merged_into_default?(pr)
          pr_querier.approvers(pr)
        else
          []
        end

      merged_by = pr_querier.merged_by(pr)

      {
        approvers: approvers,
        merged_by: merged_by
      }
    end

    private

    attr_reader :pr_querier
    attr_reader :client

    def external?(pr)
      DiscourseCodeReview.github_organizations.exclude?(pr.owner)
    end
  end
end
