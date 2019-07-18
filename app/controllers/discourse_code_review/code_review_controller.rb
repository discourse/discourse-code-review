# frozen_string_literal: true

module DiscourseCodeReview
  class CodeReviewController < ::ApplicationController
    before_action :ensure_logged_in
    before_action :ensure_staff

    skip_before_action :verify_authenticity_token, only: :webhook
    skip_before_action :ensure_logged_in, only: :webhook
    skip_before_action :ensure_staff, only: :webhook
    skip_before_action :redirect_to_login_if_required, only: :webhook
    skip_before_action :check_xhr, only: :webhook

    def webhook

      if SiteSetting.code_review_github_webhook_secret.blank?
        Rails.logger.warn("Make sure you set a secret up in code_review_github_webhook_secret")
        raise Discourse::InvalidAccess
      end

      request.body.rewind
      body = request.body.read
      signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), SiteSetting.code_review_github_webhook_secret, body)

      if !Rack::Utils.secure_compare("sha1=#{signature}", request.env['HTTP_X_HUB_SIGNATURE'])
        raise Discourse::InvalidAccess
      end

      type = request.env['HTTP_X_GITHUB_EVENT']

      # unique hash for webhook
      # delivery = request.env['HTTP_X_GITHUB_DELIVERY']

      repo = params["repository"]
      repo_name = repo["full_name"] if repo

      if ["commit_comment", "push"].include? type
        client = DiscourseCodeReview.octokit_client
        repo = GithubRepo.new(repo_name, client)
        importer = Importer.new(repo)

        if type == "commit_comment"
          commit_sha = params["comment"]["commit_id"]

          importer.sync_commit_sha(commit_sha)
        elsif type == "push"
          importer.sync_merged_commits
        end
      end

      render plain: '"ok"'
    end

    def followup
      topic = Topic.find_by(id: params[:topic_id])

      tags = topic.tags.pluck(:name)

      if !tags.include?(SiteSetting.code_review_followup_tag)
        tags -= [
          SiteSetting.code_review_approved_tag,
          SiteSetting.code_review_pending_tag
        ]

        tags << SiteSetting.code_review_followup_tag

        DiscourseTagging.tag_topic_by_names(topic, Guardian.new(current_user), tags)

        topic.add_moderator_post(
          current_user,
          nil,
          bump: false,
          post_type: Post.types[:small_action],
          action_code: "followup"
        )

        if SiteSetting.code_review_auto_assign_on_followup && topic.user.staff?
          DiscourseEvent.trigger(:assign_topic, topic, topic.user, current_user)
        end
      end

      render_next_topic(topic.category_id)

    end

    def approve

      topic = Topic.find_by(id: params[:topic_id])

      if !SiteSetting.code_review_allow_self_approval && topic.user_id == current_user.id
        raise Discourse::InvalidAccess
      end

      tags = topic.tags.pluck(:name)

      if !tags.include?(SiteSetting.code_review_approved_tag)
        tags -= [
          SiteSetting.code_review_followup_tag,
          SiteSetting.code_review_pending_tag
        ]

        tags << SiteSetting.code_review_approved_tag

        DiscourseTagging.tag_topic_by_names(topic, Guardian.new(current_user), tags)

        old_highest_post_number = topic.highest_post_number
        post =
          topic.add_moderator_post(
            current_user,
            nil,
            bump: false,
            post_type: Post.types[:small_action],
            action_code: "approved"
          )

        PostTiming.pretend_read(
          topic.id,
          old_highest_post_number,
          post.post_number
        )

        Notification.transaction do
          destroyed_notifications =
            topic.user.notifications
              .where(
                notification_type: Notification.types[:code_review_commit_approved],
              )
              .where('created_at > ?', 6.hours.ago)
              .destroy_all

          previous_approved =
            destroyed_notifications.inject(0) do |sum, notification|
              sum + JSON.parse(notification.data)['num_approved_commits'].to_i
            end

          if previous_approved == 0
            topic.user.notifications.create(
              notification_type: Notification.types[:code_review_commit_approved],
              topic_id: topic.id,
              post_number: post.post_number,
              data: { num_approved_commits: 1 }.to_json
            )
          else
            topic.user.notifications.create(
              notification_type: Notification.types[:code_review_commit_approved],
              data: { num_approved_commits: previous_approved + 1 }.to_json
            )
          end
        end

        if SiteSetting.code_review_auto_unassign_on_approve && topic.user.staff?
          DiscourseEvent.trigger(:unassign_topic, topic, current_user)
        end
      end

      render_next_topic(topic.category_id)

    end

    protected

    def render_next_topic(category_id)

      category_filter_sql = <<~SQL
        category_id NOT IN (
          SELECT category_id
          FROM category_users
          WHERE user_id = :user_id AND
            notification_level = :notification_level
        )
      SQL

      next_topic = Topic
        .joins(:tags)
        .joins("LEFT OUTER JOIN topic_users ON (topics.id = topic_users.topic_id AND topic_users.user_id = #{current_user.id})")
        .where('tags.name = ?', SiteSetting.code_review_pending_tag)
        .where('topics.user_id <> ?', current_user.id)
        .where(
          category_filter_sql,
          user_id: current_user.id,
          notification_level: CategoryUser.notification_levels[:muted]
        )
        .order('case when last_read_post_number IS NULL then 0 else 1 end asc', "case when category_id = #{category_id.to_i} then 0 else 1 end asc", 'bumped_at asc')
        .first

      url = next_topic&.relative_url

      render json: {
        next_topic_url: url
      }
    end

  end
end
