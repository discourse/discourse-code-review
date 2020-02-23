# frozen_string_literal: true

module DiscourseCodeReview
  class GithubPRPoster
    def initialize(topic:, author:, github_id:, created_at:)
      @topic = topic
      @author = author
      @github_id = github_id
      @created_at = created_at
    end

    def post_event(event)
      case event.class.tag
      when :closed
        update_closed(true)
      when :commit_thread_started
        commit_sha = event.commit_sha[0...8]

        repo_name = State::GithubRepoCategories.get_repo_name_from_topic(topic)

        discussion_topic =
          Topic.find(
            Importer.sync_commit_from_repo(repo_name, commit_sha)
          )

        body =
          "A commit that appears in this pull request is being discussed [here](#{discussion_topic.url})."

        ensure_pr_post(
          author: Discourse.system_user,
          body: body,
          post_type: :regular
        )
      when :issue_comment
        ensure_pr_post(
          body: event.body,
          post_type: :regular
        )
      when :merged
        ensure_pr_post(
          post_type: :small_action,
          action_code: 'merged'
        )
      when :review_thread_started
        body = []

        if event.context.present?
          body << <<~MD
            [quote]
            #{event.context.path}

            ```diff
            #{event.context.diff_hunk}
            ```

            [/quote]

          MD
        end

        body << event.body

        ensure_pr_post(
          body: body.join,
          post_type: :regular,
          thread_id: event.thread.github_id
        )
      when :review_comment
        ensure_pr_post(
          body: event.body,
          reply_to_github_id: event.reply_to_github_id,
          post_type: :regular,
          thread_id: event.thread.github_id
        )
      when :renamed_title
        body =
          "The title of this pull request changed from \"#{event.previous_title}\" to \"#{event.new_title}"

        ensure_pr_post(body: body, post_type: :small_action, action_code: 'renamed') do |post|
          topic = post.topic

          issue_number = topic.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_ISSUE_NUMBER]

          topic.title = "#{event.new_title} (PR ##{issue_number})"
          topic.save!(validate: false)
        end
      when :reopened
        update_closed(false)
      end
    end

    private

    attr_reader :topic
    attr_reader :author
    attr_reader :github_id
    attr_reader :created_at

    def get_last_post
      Post
        .where(topic_id: topic.id)
        .order('post_number DESC')
        .limit(1)
        .first
    end

    def update_closed(closed)
      unless_pr_post do
        topic.update_status('closed', closed, author)

        last_post = get_last_post

        last_post.created_at = created_at
        last_post.skip_validation = true
        last_post.save!

        last_post.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID] = github_id
        last_post.save_custom_fields
      end
    end

    def find_pr_post(github_id)
      Post.where(
        id:
          PostCustomField
            .select(:post_id)
            .where(name: DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID, value: github_id)
            .limit(1)
      ).first
    end

    def unless_pr_post
      # Without this mutex, concurrent transactions can create duplicate
      # posts
      DistributedMutex.synchronize('code-review:sync-pull-request-post') do
        ActiveRecord::Base.transaction(requires_new: true) do
          post = find_pr_post(github_id)

          if post.nil?
            yield
          end
        end
      end
    end

    def ensure_pr_post(post_type:, body: nil, action_code: nil, reply_to_github_id: nil, author: @author, thread_id: nil)
      unless_pr_post do
        reply_to_post_number =
          if reply_to_github_id.present?
            Post.where(
              id:
                PostCustomField
                  .select(:post_id)
                  .where(name: DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID, value: reply_to_github_id)
                  .limit(1)
            ).pluck(:post_number).first
          end

        post =
          DiscourseCodeReview.without_rate_limiting do
            PostCreator.create!(
              author,
              topic_id: topic.id,
              created_at: created_at,
              raw: body,
              reply_to_post_number: reply_to_post_number,
              post_type: Post.types[post_type],
              action_code: action_code,
              skip_validations: true
            )
          end

        post.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID] = github_id
        post.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_THREAD_ID] = thread_id if thread_id.present?
        post.save_custom_fields

        yield post if block_given?
      end
    end
  end
end
