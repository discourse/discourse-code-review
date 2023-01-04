# frozen_string_literal: true

module DiscourseCodeReview
  class GithubRepo
    attr_reader :name, :octokit_client, :repo_id

    LAST_COMMIT = "last commit"
    MAX_DIFF_LENGTH = 8000

    def initialize(name, octokit_client, commit_querier, repo_id: nil)
      @owner, @repo = name.split("/")
      @name = name
      @octokit_client = octokit_client
      @commit_querier = commit_querier
      @repo_id = repo_id
    end

    def clean_name
      @name.gsub(/[^a-z0-9]/i, "_")
    end

    def default_branch
      @default_branch ||= "origin/#{octokit_client.repository(@name)["default_branch"]}"
    end

    def last_local_commit
      PluginStore.get(DiscourseCodeReview::PluginName, LAST_COMMIT + @name)
    end

    def last_commit
      commit_hash = last_local_commit

      if commit_hash.present? && !commit_hash_valid?(commit_hash)
        Rails.logger.warn(
          "Discourse Code Review: Failed to detect commit hash `#{commit_hash}` in #{path}, resetting last commit hash.",
        )
        commit_hash = nil
      end

      if !commit_hash
        commits = [SiteSetting.code_review_catch_up_commits, 1].max - 1
        commit_hash = git_repo.n_before(default_branch, commits)
        self.last_commit = commit_hash
      end

      commit_hash
    end

    def last_commit=(v)
      PluginStore.set(DiscourseCodeReview::PluginName, LAST_COMMIT + @name, v)
      v
    end

    def commit_hash_valid?(hash)
      git_repo.fetch
      git_repo.commit_hash_valid?(hash)
    end

    def default_branch_contains?(ref)
      git_repo.fetch
      git_repo.contains?(default_branch, ref)
    end

    def commit_comments(commit_sha)
      git_repo.fetch

      octokit_client
        .commit_comments(@name, commit_sha)
        .map do |hash|
          line_content = nil

          if hash[:path].present? && hash[:position].present?
            line_content = @git_repo.diff_excerpt(hash[:commit_id], hash[:path], hash[:position])
          end

          login = hash[:user][:login] if hash[:user]
          {
            url: hash[:html_url],
            id: hash[:id],
            login: login,
            position: hash[:position],
            line: hash[:line],
            path: hash[:path],
            commit_hash: hash[:commit_id],
            created_at: hash[:created_at],
            updated_at: hash[:updated_at],
            body: hash[:body],
            line_content: line_content,
          }
        end
    end

    def commit(hash)
      commits_since(hash, single: true).first
    rescue Rugged::ReferenceError
      nil
    end

    def commits_since(ref = nil, merge_github_info: true, pull: true, single: false)
      git_repo.fetch if pull

      ref ||= last_commit

      commit_chunks =
        if single
          [[git_repo.rev_parse(ref)]]
        else
          git_repo.commit_oids_since(ref, default_branch).each_slice(30)
        end

      lookup = {}
      if merge_github_info
        commit_chunks.each do |chunk|
          @commit_querier
            .commits_authors(@owner, @repo, chunk)
            .each do |_, commit_info|
              lookup[commit_info.oid] = {
                author_login: commit_info.author&.login,
                author_id: commit_info.author&.id,
                committer_login: commit_info.committer&.login,
                committer_id: commit_info.committer&.id,
              }
            end
        end
      end

      commits = (single ? [git_repo.commit(ref)] : git_repo.commits_since(ref, default_branch))

      commits
        .map do |commit|
          hash = commit.oid
          body = commit.message
          name = commit.author_name
          email = commit.author_email
          authored_at = commit.author_time
          subject = commit.summary
          truncated = false
          diff = commit.diff

          if diff
            diff = diff.scrub
            if diff.length > MAX_DIFF_LENGTH
              diff_lines = diff[0..MAX_DIFF_LENGTH].split("\n")
              diff_lines.pop
              diff = diff_lines.join("\n")
              truncated = true
            end
          else
            diff = "MERGE COMMIT"
          end

          github_data = lookup[hash] || {}

          {
            hash: hash,
            name: name,
            email: email,
            subject: subject,
            body: body,
            date: authored_at,
            diff: diff,
            diff_truncated: truncated,
          }.merge(github_data)
        end
        .reverse
    end

    def followees(ref)
      result = []

      git_repo
        .commit(ref)
        .message
        .lines
        .each_with_index do |line, index|
          next if index == 0 && line =~ /^revert\b/i
          data = line[/follow.*?(\h{7,})/i, 1]
          result << data if data
        end

      result
    end

    def path
      @path ||=
        begin
          FileUtils.mkdir_p(
            Rails.root + "tmp/code-review-repo-#{ENV["TEST_ENV_NUMBER"].presence || "0"}",
          )

          (
            Rails.root +
              "tmp/code-review-repo-#{ENV["TEST_ENV_NUMBER"].presence || "0"}/#{clean_name}"
          ).to_s
        end
    end

    # for testing
    def path=(v)
      @path = v
    end

    def url
      @url ||= "https://github.com/#{@name}.git"
    end

    def credentials
      @credentials ||=
        begin
          github_token = SiteSetting.code_review_github_token

          if (SiteSetting.code_review_allow_private_clone && github_token.present?)
            Rugged::Credentials::UserPassword.new(username: github_token, password: "")
          end
        end
    end

    def git_repo
      @git_repo ||= Source::GitRepo.new(url, path, credentials: credentials)
    end
  end
end
