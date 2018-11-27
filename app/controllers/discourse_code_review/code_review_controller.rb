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

      hijack do
        if ["commit_comment", "push"].include? type
          client = DiscourseCodeReview.octokit_client
          repo = GithubRepo.new(repo_name, client)
          importer = Importer.new(repo)

          if type == "commit_comment"
            importer.import_comments
          elsif type == "push"
            importer.import_commits
          end
        end

        render plain: '"ok"'
      end
    end

    def followup
      topic = Topic.find_by(id: params[:topic_id])

      tags = topic.tags.pluck(:name)

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

      render_next_topic(topic.category_id)

    end

    def approve

      topic = Topic.find_by(id: params[:topic_id])

      if !SiteSetting.code_review_allow_self_approval && topic.user_id == current_user.id
        raise Discourse::InvalidAccess
      end

      tags = topic.tags.pluck(:name)

      tags -= [
        SiteSetting.code_review_followup_tag,
        SiteSetting.code_review_pending_tag
      ]

      tags << SiteSetting.code_review_approved_tag

      DiscourseTagging.tag_topic_by_names(topic, Guardian.new(current_user), tags)

      topic.add_moderator_post(
        current_user,
        nil,
        bump: false,
        post_type: Post.types[:small_action],
        action_code: "approved"
      )

      render_next_topic(topic.category_id)

    end

    protected

    def render_next_topic(category_id)
      next_topic = Topic
        .joins(:tags)
        .where('tags.name = ?', SiteSetting.code_review_pending_tag)
        .where(category_id: category_id)
        .where('user_id <> ?', current_user.id)
        .order('bumped_at asc')
        .first

      url = next_topic&.relative_url

      render json: {
        next_topic_url: url
      }
    end

  end
end
