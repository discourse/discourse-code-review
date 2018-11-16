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

    if SiteSetting.code_review_enabled && SiteSetting.code_review_github_repo.present?
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

  module ::DiscourseCodeReview
    PluginName = 'discourse-code-review'

    class Engine < ::Rails::Engine
      engine_name 'code-review'
      isolate_namespace DiscourseCodeReview
    end

    UserToken = 'github user token'
    LastCommit = 'last commit'
    CommitHash = 'commit hash'
    GithubId = 'github id'
    GithubLogin = 'github login'
    CommentPage = 'comment page'

    def self.last_commit
      PluginStore.get(DiscourseCodeReview::PluginName, LastCommit) ||
        (self.last_commit = git('rev-parse HEAD~30'))
    end

    def self.last_commit=(v)
      PluginStore.set(DiscourseCodeReview::PluginName, LastCommit, v)
      v
    end

    def self.current_comment_page
      (PluginStore.get(DiscourseCodeReview::PluginName, CommentPage) || 1).to_i
    end

    def self.current_comment_page=(v)
      PluginStore.set(DiscourseCodeReview::PluginName, CommentPage, v)
      v
    end

    LINE_END = "52fc72dfa9cafa9da5e6266810b884ae"
    FEILD_END = "52fc72dfa9cafa9da5e6266810b884ff"

    MAX_DIFF_LENGTH = 8000

    def self.commit_comments(page)

      Octokit.list_commit_comments(SiteSetting.code_review_github_repo, page: page).map do |hash|
        login = hash[:user][:login] if hash[:user]
        {
          url: hash[:html_url],
          id: hash[:id],
          login: login,
          position: hash[:position],
          line: hash[:line],
          commit_hash: hash[:commit_id],
          created_at: hash[:created_at],
          updated_at: hash[:updated_at],
          body: hash[:body]
        }
      end

    end

    def self.commits_since(hash = nil)
      git("pull")
      hash ||= last_commit

      github_info = []

      commits = git("log #{hash}.. --pretty=%H").split("\n").map { |x| x.strip }

      commits.each_slice(30).each do |x|
        commits = Octokit.commits(SiteSetting.code_review_github_repo, sha: x.first)
        github_info.concat(commits)
      end

      lookup = {}
      github_info.each do |commit|
        lookup[commit.sha] = {
          author_login: commit&.author&.login,
          author_id: commit&.author&.id,
          committer_login: commit&.committer&.login,
          committer_id: commit&.committer&.id,
        }
      end

      # hash name email subject body
      format = %w{%H %aN %aE %s %B %at}.join(FEILD_END) << LINE_END

      data = git("log #{hash}.. --pretty='#{format}'")

      data.split(LINE_END).map do |line|
        fields = line.split(FEILD_END).map { |f| f.strip if f }

        hash = fields[0].strip

        diff = git("show --format=email #{hash}")

        abbrev = diff.length > MAX_DIFF_LENGTH
        if abbrev
          diff = diff[0..MAX_DIFF_LENGTH]
        end

        github_data = lookup[hash] || {}

        {
          hash: hash,
          name: fields[1],
          email: fields[2],
          subject: fields[3],
          body: fields[4],
          date: Time.at(fields[5].to_i).to_datetime,
          diff: diff,
          diff_abbrev: abbrev
        }.merge(github_data)

      end.reverse

    end

    def self.git(command)
      raise "No repo configured" if SiteSetting.code_review_github_repo.blank?
      path = (Rails.root + "tmp/code-review-repo").to_s

      if !File.exist?(path)
        `git clone https://github.com/#{SiteSetting.code_review_github_repo}.git '#{path}'`
      end

      Dir.chdir(path) do
        `git #{command}`.strip
      end
    end
  end

  require File.expand_path("../jobs/import_commits.rb", __FILE__)

  class ::DiscourseCodeReview::CodeReviewController < ::ApplicationController
    before_action :ensure_logged_in
    before_action :ensure_staff

    def approve
      topic = Topic.find_by(id: params[:topic_id])

      PostRevisor.new(topic.ordered_posts.first, topic)
        .revise!(current_user,
          category_id: SiteSetting.code_review_approved_category_id)

      topic.add_moderator_post(
        current_user,
        nil,
        bump: false,
        post_type: Post.types[:small_action],
        action_code: "approved"
      )

      next_topic = Topic
        .where(category_id: SiteSetting.code_review_pending_category_id)
        .where('topics.id not in (select categories.topic_id from categories where categories.id = category_id)')
        .order('bumped_at asc')
        .first

      url = next_topic&.relative_url

      render json: {
        next_topic_url: url
      }
    end

  end

  DiscourseCodeReview::Engine.routes.draw do
    post '/approve' => 'code_review#approve'
  end

  Discourse::Application.routes.append do
    mount ::DiscourseCodeReview::Engine, at: '/code-review'
  end

  if !Category.exists?(id: SiteSetting.code_review_pending_category_id)
    category = Category.find_by(name: 'pending')
    category ||= Category.create!(
      name: 'pending',
      user: Discourse.system_user
    )

    SiteSetting.code_review_pending_category_id = category.id
  end

  if !Category.exists?(id: SiteSetting.code_review_approved_category_id)
    category = Category.find_by(name: 'approved')
    category ||= Category.create!(
      name: 'approved',
      user: Discourse.system_user
    )

    SiteSetting.code_review_approved_category_id = category.id
  end

  on(:post_process_cooked) do |doc, post|
    if post.post_number > 1 && post.raw.present? && (topic = post.topic) && (hash = topic.custom_fields[DiscourseCodeReview::CommitHash])

      if !post.custom_fields[DiscourseCodeReview::GithubId] && post.user
        if token = post.user.custom_fields[DiscourseCodeReview::UserToken]
          client = Octokit::Client.new(access_token: token)
          comment = client.create_commit_comment(SiteSetting.code_review_github_repo, hash, post.raw)
          p comment
          post.custom_fields[DiscourseCodeReview::GithubId] = comment.id
          post.save_custom_fields
        end
      end

    end
  end
end
