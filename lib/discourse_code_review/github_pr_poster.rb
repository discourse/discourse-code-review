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

    def update_closed(closed)
      State::Helpers.ensure_closed_state_with_nonce(
        closed: closed,
        created_at: created_at,
        nonce_name: DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID,
        nonce_value: github_id,
        topic: topic,
        user: author,
      )
    end

    def ensure_pr_post(post_type:, body: nil, action_code: nil, reply_to_github_id: nil, author: @author, thread_id: nil)
      reply_to_post_number =
        if reply_to_github_id
          State::Helpers.posts_with_custom_field(
            topic_id: topic.id,
            name: DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID,
            value: reply_to_github_id,
          ).pluck_first(:post_number)
        end

      custom_fields = {}

      if thread_id.present?
        custom_fields[
          DiscourseCodeReview::GithubPRSyncer::GITHUB_THREAD_ID
        ] = thread_id
      end

      post =
        State::Helpers.ensure_post_with_nonce(
          action_code: action_code,
          created_at: created_at,
          custom_fields: custom_fields,
          nonce_name: DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID,
          nonce_value: github_id,
          post_type: Post.types[post_type],
          raw: body,
          reply_to_post_number: reply_to_post_number,
          skip_validations: true,
          topic_id: topic.id,
          user: author,
        )

      yield post if block_given?
    end
  end
end
