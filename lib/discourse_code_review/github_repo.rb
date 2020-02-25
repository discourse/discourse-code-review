# frozen_string_literal: true

module DiscourseCodeReview
  class GithubRepo
    attr_reader :name, :octokit_client

    LAST_COMMIT = 'last commit'
    MAX_DIFF_LENGTH = 8000

    def initialize(name, octokit_client, commit_querier)
      @owner, @repo = name.split('/')
      @name = name
      @octokit_client = octokit_client
      @commit_querier = commit_querier
    end

    def clean_name
      @name.gsub(/[^a-z0-9]/i, "_")
    end

    def last_commit
      commit_hash = PluginStore.get(DiscourseCodeReview::PluginName, LAST_COMMIT + @name)
      if commit_hash.present? && !commit_hash_valid?(commit_hash)
        Rails.logger.warn("Discourse Code Review: Failed to detect commit hash `#{commit_hash}` in #{path}, resetting last commit hash.")
        commit_hash = nil
      end

      if !commit_hash
        commits = [SiteSetting.code_review_catch_up_commits, 1].max - 1
        commit_hash = git_repo.n_before('origin/master', commits)
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

    def master_contains?(ref)
      git_repo.fetch
      git_repo.master_contains?(ref)
    end

    def commit_comments(commit_sha)
      git_repo.fetch

      octokit_client.commit_comments(@name, commit_sha).map do |hash|
        line_content = nil

        if hash[:path].present? && hash[:position].present?
          diff =
            @git_repo.diff_excerpt(
              hash[:commit_id],
              hash[:path],
              hash[:position],
            )
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
      begin
        commits_since(hash, single: true).first
      rescue Rugged::ReferenceError
        nil
      end
    end

    def commits_since(ref = nil, merge_github_info: true, pull: true, single: false)
      if pull
        git_repo.fetch
      end

      ref ||= last_commit

      commit_chunks =
        if single
          [[git_repo.rev_parse(ref)]]
        else
          git_repo
            .commits_since(ref, 'origin/master')
            .each_oid
            .each_slice(30)
        end

      lookup = {}
      if merge_github_info
        commit_chunks.each do |chunk|
          @commit_querier.commits_authors(@owner, @repo, chunk).each do |_, commit_info|
            lookup[commit_info.oid] = {
              author_login: commit_info.author&.login,
              author_id: commit_info.author&.id,
              committer_login: commit_info.committer&.login,
              committer_id: commit_info.committer&.id,
            }
          end
        end
      end

      commits =
        if single
          [git_repo.commit(ref)]
        else
          git_repo.commits_since(ref, 'origin/master')
        end

      commits.map do |commit|
        hash = commit.oid
        body = commit.message
        name = commit.author[:name]
        email = commit.author[:email]
        authored_at = commit.author[:time]
        subject = commit.summary
        truncated = false

        if commit.parents.size == 1
          diff = commit.parents[0].diff(commit).patch
          if diff.length > MAX_DIFF_LENGTH
            diff_lines = diff[0..MAX_DIFF_LENGTH].split("\n")
            diff_lines.pop
            diff = diff_lines.join('\n')
            truncated = true
          end
        else
          diff = ""
        end

        github_data = lookup[hash] || {}

        {
          hash: hash,
          name: name,
          email: email,
          subject: subject,
          body: body,
          date: authored_at.to_datetime,
          diff: diff,
          diff_truncated: truncated,
        }.merge(github_data)
      end.reverse
    end

    def followees(ref)
      git_repo
        .trailers(ref)
        .select { |x| x.first == 'Follow-up-to' }
        .map(&:second)
    end

    def path
      @path ||= begin
        FileUtils.mkdir_p(Rails.root + "tmp/code-review-repo")

        (Rails.root + "tmp/code-review-repo/#{clean_name}").to_s
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
      @credentials ||= begin
        github_token = SiteSetting.code_review_github_token

        if (SiteSetting.code_review_allow_private_clone && github_token.present?)
          Rugged::Credentials::UserPassword.new(
            username: github_token,
            password: '',
          )
        end
      end
    end

    def git_repo
      @git_repo ||= GitRepo.new(url, path, credentials: credentials)
    end
  end
end
