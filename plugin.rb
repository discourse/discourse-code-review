# frozen_string_literal: true

# name: discourse-code-review
# about: use discourse for after the fact code reviews
# version: 0.1
# authors: Sam Saffron
# url: https://github.com/discourse/discourse-code-review

# match version in discourse dev
gem 'public_suffix', '3.0.3'
gem 'addressable', '2.5.2'
gem 'sawyer', '0.8.1'
gem 'octokit', '4.9.0'

enabled_site_setting :code_review_enabled

require_dependency 'auth/github_authenticator'
module HackGithubAuthenticator

  def after_authenticate(auth_token, existing_account: nil)
    result = super(auth_token, existing_account: existing_account)

    if SiteSetting.code_review_enabled?
      if user_id = result.user&.id
        token = auth_token.credentials.token

        user = result.user
        user.custom_fields[DiscourseCodeReview::GithubId] = auth_token[:uid]
        user.custom_fields[DiscourseCodeReview::GithubLogin] = auth_token.info.nickname
        user.save_custom_fields
      end
    end

    result
  end
end

class ::Auth::GithubAuthenticator
  prepend HackGithubAuthenticator
end

after_initialize do

  if !SiteSetting.tagging_enabled
    Rails.logger.warn("The code review plugin requires tagging, enabling it!")
    SiteSetting.tagging_enabled = true
  end

  module ::DiscourseCodeReview
    PluginName = 'discourse-code-review'

    class APIUserError < StandardError
    end

    class Engine < ::Rails::Engine
      engine_name 'code-review'
      isolate_namespace DiscourseCodeReview
    end

    CommitHash = 'commit hash'
    GithubId = 'github id'
    GithubLogin = 'github login'
    CommentPath = 'comment path'
    CommentPosition = 'comment position'

    def self.octokit_bot_client
      token = SiteSetting.code_review_github_token

      if token.nil? || token.empty?
        raise APIUserError, "code_review_github_token not set"
      end

      Octokit::Client.new(access_token: token)
    end

    def self.octokit_client
      self.octokit_bot_client
    rescue APIUserError
      Octokit::Client.new
    end

    def self.sync_post_to_github(client, post)
      topic = post.topic
      hash = topic&.custom_fields[DiscourseCodeReview::CommitHash]
      user = post.user

      if post.post_number > 1 && !post.whisper? && post.raw.present? && topic && hash && user
        if !post.custom_fields[DiscourseCodeReview::GithubId]
          fields = post.reply_to_post&.custom_fields || {}
          path = fields[DiscourseCodeReview::CommentPath]
          position = fields[DiscourseCodeReview::CommentPosition]

          if repo = post.topic.category.custom_fields[DiscourseCodeReview::Importer::GithubRepoName]
            post_user_name = user.name || user.username

            github_post_contents = [
              "[#{post_user_name} posted](#{post.full_url}):",
              '',
              post.raw
            ].join("\n")

            comment = client.create_commit_comment(repo, hash, github_post_contents, path, nil, position)
            post.custom_fields[DiscourseCodeReview::GithubId] = comment.id
            post.custom_fields[DiscourseCodeReview::CommentPath] = path if path.present?
            post.custom_fields[DiscourseCodeReview::CommentPosition] = position if position.present?
            post.save_custom_fields
          end
        end
      end
    end
  end

  require File.expand_path("../app/controllers/discourse_code_review/code_review_controller.rb", __FILE__)
  require File.expand_path("../lib/discourse_code_review/importer.rb", __FILE__)
  require File.expand_path("../lib/discourse_code_review/github_repo.rb", __FILE__)

  DiscourseCodeReview::Engine.routes.draw do
    post '/approve' => 'code_review#approve'
    post '/followup' => 'code_review#followup'
    post '/webhook' => 'code_review#webhook'
  end

  Discourse::Application.routes.append do
    mount ::DiscourseCodeReview::Engine, at: '/code-review'
  end

  on(:post_process_cooked) do |doc, post|
    if SiteSetting.code_review_sync_to_github?
      client = DiscourseCodeReview.octokit_bot_client
      DiscourseCodeReview.sync_post_to_github(client, post)
    end
  end

  on(:before_post_process_cooked) do |doc, post|
    unless post.topic.custom_fields[DiscourseCodeReview::CommitHash].present? && post.post_number == 1
      doc = DiscourseCodeReview::Importer.new(nil).auto_link_commits(post.raw, doc)[2]
    end
  end
end

Rake::Task.define_task code_review_delete_user_github_access_tokens: :environment do
  num_deleted = UserCustomField.where(name: 'github user token').delete_all
  puts "deleted #{num_deleted} user_custom_fields"
end
