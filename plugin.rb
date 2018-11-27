# name: discourse-code-review
# about: use discourse for after the fact code reviews
# version: 0.1
# authors: Sam Saffron
# url: https://github.com/discourse/discourse-code-review

# match version in discourse dev
begin
  require 'octokit'
rescue LoadError
  gem 'octokit', '4.9.0'
end

enabled_site_setting :code_review_enabled

require_dependency 'auth/github_authenticator'
module HackGithubAuthenticator

  def after_authenticate(auth_token, existing_account: nil)
    result = super(auth_token, existing_account: existing_account)

    if SiteSetting.code_review_enabled
      if user_id = result.user&.id
        token = auth_token.credentials.token

        user = result.user
        user.custom_fields[DiscourseCodeReview::UserToken] = token
        user.custom_fields[DiscourseCodeReview::GithubId] = auth_token[:uid]
        user.custom_fields[DiscourseCodeReview::GithubLogin] = auth_token.info.nickname
        user.save_custom_fields

      end
    end

    result
  end

  def register_middleware(omniauth)
    scope = "user:email"

    if SiteSetting.code_review_enabled
      scope = "user:email,repo"
    end

    scope = "user:email,repo"

    omniauth.provider :github,
           setup: lambda { |env|
             strategy = env["omniauth.strategy"]
              strategy.options[:client_id] = SiteSetting.github_client_id
              strategy.options[:client_secret] = SiteSetting.github_client_secret
           },
           scope: scope
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

    class Engine < ::Rails::Engine
      engine_name 'code-review'
      isolate_namespace DiscourseCodeReview
    end

    UserToken = 'github user token'
    CommitHash = 'commit hash'
    GithubId = 'github id'
    GithubLogin = 'github login'

    def self.octokit_client
      client = Octokit::Client.new

      if username = SiteSetting.code_review_api_username.presence
        username = username.downcase
        id = User.where(username_lower: username).pluck(:id).first
        if id && (token = UserCustomField.where(user_id: id, name: DiscourseCodeReview::UserToken).pluck(:value).first)
          client = Octokit::Client.new(access_token: token)
        end
      end

      client
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
    if post.post_number > 1 && !post.whisper? && post.raw.present? && (topic = post.topic) && (hash = topic.custom_fields[DiscourseCodeReview::CommitHash])

      if !post.custom_fields[DiscourseCodeReview::GithubId] && post.user
        if token = post.user.custom_fields[DiscourseCodeReview::UserToken]
          client = Octokit::Client.new(access_token: token)

          if repo = post.topic.category.custom_fields[DiscourseCodeReview::Importer::GithubRepoName]
            comment = client.create_commit_comment(repo, hash, post.raw)
            post.custom_fields[DiscourseCodeReview::GithubId] = comment.id
            post.save_custom_fields
          end
        end
      end

    end
  end
end
