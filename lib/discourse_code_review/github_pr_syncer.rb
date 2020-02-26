# frozen_string_literal: true

module DiscourseCodeReview
  class GithubPRSyncer
    GITHUB_NODE_ID = "github node id"
    GITHUB_ISSUE_NUMBER = "github issue number"
    GITHUB_THREAD_ID = "github thread id"

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
        State::GithubRepoCategories
          .ensure_category(
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
      State::GithubRepoCategories
        .github_repo_category_fields.each do |field|
          sync_repo(field.value)
        end
    end

    def sync_associated_pull_requests(repo_name, git_commit)
      pr_service.associated_pull_requests(repo_name, git_commit).each do |pr|
        sync_pull_request(repo_name, pr.issue_number)
      end
    end

    def apply_github_approves(repo_name, commit_hash)
      topic =
        Topic
          .where(
            id:
              TopicCustomField
                .where(
                  name: COMMIT_HASH,
                  value: commit_hash
                )
                .limit(1)
                .select(:topic_id)
          )
          .first

      if topic
        pr_service.associated_pull_requests(repo_name, commit_hash).each do |pr|
          merge_info = pr_service.merge_info(pr)
          if !merge_info[:merged_by].nil?
            merged_by = ensure_actor(merge_info[:merged_by])

            approvers =
              merge_info[:approvers]
                .map(&method(:ensure_actor))
                .select(&:staff?)
                .select { |user|
                  SiteSetting.code_review_allow_self_approval || topic.user_id != user.id
                }

            State::CommitApproval.approve(
              topic,
              approvers,
              pr: pr,
              merged_by: merged_by
            )
          end
        end
      end
    end

    def mirror_pr_post(post)
      topic = post.topic
      user = post.user

      conditions = [
        post.post_number > 1,
        post.post_type == Post.types[:regular],
        post.custom_fields[GITHUB_NODE_ID].nil?
      ]

      if conditions.all?
        repo_name =
          topic.category.custom_fields[
            State::GithubRepoCategories::GITHUB_REPO_NAME
          ]

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

          response =
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

          post.custom_fields[GITHUB_NODE_ID] = response[:node_id]
          post.save_custom_fields
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
      # Without this mutex, concurrent transactions can create duplicate
      # topics
      DistributedMutex.synchronize('code-review:sync-pull-request-topic') do
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
end
