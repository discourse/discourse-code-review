# frozen_string_literal: true

module DiscourseCodeReview
  class GithubPRSyncer
    GITHUB_NODE_ID = "github node id"
    GITHUB_ISSUE_NUMBER = "github issue number"
    GITHUB_THREAD_ID = "github thread id"

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

          repo_name = GithubCategorySyncer.get_repo_name_from_topic(topic)

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

            issue_number = topic.custom_fields[GITHUB_ISSUE_NUMBER]

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
          last_post.save!

          last_post.custom_fields[GITHUB_NODE_ID] = github_id
          last_post.save_custom_fields
        end
      end

      def find_pr_post(github_id)
        Post.where(
          id:
            PostCustomField
              .select(:post_id)
              .where(name: GITHUB_NODE_ID, value: github_id)
              .limit(1)
        ).first
      end

      def unless_pr_post
        ActiveRecord::Base.transaction(requires_new: true) do
          post = find_pr_post(github_id)

          if post.nil?
            yield
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
                    .where(name: GITHUB_NODE_ID, value: reply_to_github_id)
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

          post.custom_fields[GITHUB_NODE_ID] = github_id
          post.custom_fields[GITHUB_THREAD_ID] = thread_id if thread_id.present?
          post.save_custom_fields

          yield post if block_given?
        end
      end
    end

    def initialize(pr_service, user_syncer)
      @pr_service = pr_service
      @user_syncer = user_syncer
    end

    def sync_pull_request(repo_name, issue_number)
      owner, name = repo_name.split('/', 2)

      pr =
        PullRequest.new(
          owner: owner,
          name: name,
          issue_number: issue_number
        )

      pr_data = pr_service.pull_request_data(pr)

      category =
        GithubCategorySyncer.ensure_category(
          repo_name: repo_name
        )

      url =
        "https://github.com/#{repo_name}/pull/#{issue_number}"

      topic =
        ensure_pr_topic(
          category: category,
          author: ensure_actor(pr_data.author),
          github_id: pr_data.github_id,
          created_at: pr_data.created_at,
          title: pr_data.title,
          body: pr_data.body,
          url: url,
          issue_number: issue_number
        )

      pr_service.pull_request_events(pr).each do |event_info, event|
        poster =
          GithubPRPoster.new(
            topic: topic,
            author: ensure_actor(event_info.actor),
            github_id: event_info.github_id,
            created_at: event_info.created_at
          )

        poster.post_event(event)
      end
    end

    def sync_repo(repo_name)
      pr_service.pull_requests(repo_name).each do |pr|
        sync_pull_request(repo_name, pr.issue_number)
      end
    end

    def sync_all
      GithubCategorySyncer.github_repo_category_fields.each do |field|
        sync_repo(field.value)
      end
    end

    def sync_associated_pull_requests(repo_name, git_commit)
      pr_service.associated_pull_requests(repo_name, git_commit).each do |pr|
        sync_pull_request(repo_name, pr.issue_number)
      end
    end

    def mirror_pr_post(post)
      topic = post.topic
      user = post.user

      if post.post_number > 1 && !post.whisper? && post.custom_fields[GITHUB_NODE_ID].nil?
        repo_name = topic.category.custom_fields[GithubCategorySyncer::GITHUB_REPO_NAME]
        issue_number = topic.custom_fields[GITHUB_ISSUE_NUMBER]

        if repo_name && issue_number
          issue_number = issue_number.to_i
          reply_to_number = post.reply_to_post_number

          reply_to =
            if reply_to_number.present?
              topic.posts.where(post_number: reply_to_number).first
            end

          thread_id =
            if reply_to.present?
              reply_to.custom_fields[GITHUB_THREAD_ID]
            end

          post_user_name = user.name || user.username

          github_post_contents = [
            "[#{post_user_name} posted](#{post.full_url}):",
            '',
            post.raw
          ].join("\n")

          if thread_id
            @pr_service.create_review_comment(
              repo_name,
              issue_number,
              github_post_contents,
              thread_id
            )
          else
            @pr_service.create_issue_comment(
              repo_name,
              issue_number,
              github_post_contents
            )
          end
        end
      end
    end

    private

    attr_reader :pr_service
    attr_reader :user_syncer

    def ensure_actor(actor)
      github_login = actor.github_login
      user_syncer.ensure_user(
        name: github_login,
        github_login: github_login
      )
    end

    def find_pr_topic(github_id)
      Topic.where(
        id:
          TopicCustomField
            .select(:topic_id)
            .where(name: GITHUB_NODE_ID, value: github_id)
            .limit(1)
      ).first
    end

    def ensure_pr_topic(category:, author:, github_id:, created_at:, title:, body:, url:, issue_number:)
      ActiveRecord::Base.transaction(requires_new: true) do
        topic = find_pr_topic(github_id)

        if topic.nil?
          topic_title = "#{title} (PR ##{issue_number})"
          raw = "#{body}\n\n[<small>GitHub</small>](#{url})"

          topic =
            DiscourseCodeReview.without_rate_limiting do
              PostCreator.create!(
                author,
                category: category.id,
                created_at: created_at,
                title: topic_title,
                raw: raw,
                tags: [SiteSetting.code_review_pull_request_tag],
                skip_validations: true
              ).topic
            end

          topic.custom_fields[GITHUB_NODE_ID] = github_id
          topic.custom_fields[GITHUB_ISSUE_NUMBER] = issue_number.to_s
          topic.save_custom_fields
        end

        topic
      end
    end
  end
end
