# frozen_string_literal: true

module DiscourseCodeReview
  class ReposController < ::ApplicationController
    before_action :set_organization
    before_action :set_repo, only: [:has_configured_webhook, :configure_webhook]

    def index
      repository_names = client.organization_repositories(organization).map(&:name)
      render_json_dump(repository_names)
    rescue Octokit::Unauthorized
      render json: failed_json.merge(
        error: I18n.t("discourse_code_review.bad_github_credentials_error")
      ), status: 401
    end

    def has_configured_webhook
      hook = get_hook

      has_configured_webhook = hook.present?
      has_configured_webhook &&= hook[:events].to_set == webhook_events.to_set
      has_configured_webhook &&= hook[:config][:url] == webhook_config[:url]
      has_configured_webhook &&= hook[:config][:content_type] == webhook_config[:content_type]
      render_json_dump(
        has_configured_webhook: has_configured_webhook
      )
    rescue Octokit::NotFound
      render json: failed_json.merge(
        error: I18n.t("discourse_code_review.bad_github_permissions_error")
      ), status: 400
    end

    def configure_webhook
      hook = get_hook

      if hook.present?
        client.edit_hook(
          full_repo_name,
          hook[:id],
          'web',
          webhook_config,
          events: webhook_events,
          active: true
        )
      else
        client.create_hook(
          full_repo_name,
          'web',
          webhook_config,
          events: webhook_events,
          active: true
        )
      end

      render_json_dump(
        has_configured_webhook: true
      )
    end

    private

    attr_reader :organization
    attr_reader :repo

    def full_repo_name
      "#{organization}/#{repo}"
    end

    def set_organization
      @organization = params[:organization_id]
    end

    def set_repo
      @repo = params[:id]
    end

    def client
      DiscourseCodeReview.octokit_bot_client
    end

    def get_hook
      client
        .hooks(full_repo_name)
        .select { |hook|
          config = hook[:config]
          url = URI.parse(config[:url])

          url.hostname == Discourse.current_hostname && url.path == '/code-review/webhook'
        }
        .first
    end

    def webhook_config
      {
        url: "https://#{Discourse.current_hostname}/code-review/webhook",
        content_type: 'json',
        secret: SiteSetting.code_review_github_webhook_secret
      }
    end

    def webhook_events
      [
        "commit_comment",
        "issue_comment",
        "pull_request",
        "pull_request_review",
        "pull_request_review_comment",
        "push"
      ]
    end
  end
end
