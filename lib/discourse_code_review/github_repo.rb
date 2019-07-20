# frozen_string_literal: true

module DiscourseCodeReview
  class GithubRepo

    attr_reader :name, :octokit_client

    LastCommit = 'last commit'
    CommentPage = 'comment page'

    LINE_END = "52fc72dfa9cafa9da5e6266810b884ae"
    FIELD_END = "52fc72dfa9cafa9da5e6266810b884ff"

    MAX_DIFF_LENGTH = 8000

    def initialize(name, octokit_client)
      @name = name
      @octokit_client = octokit_client
    end

    def clean_name
      @name.gsub(/[^a-z0-9]/i, "_")
    end

    def last_commit
      commit_hash = PluginStore.get(DiscourseCodeReview::PluginName, LastCommit + @name)
      if commit_hash.present? && !commit_hash_valid?(commit_hash)
        Rails.logger.warn("Discourse Code Review: Failed to detect commit hash `#{commit_hash}` in #{path}, resetting last commit hash.")
        commit_hash = nil
      end
      if !commit_hash
        commits = [SiteSetting.code_review_catch_up_commits, 1].max - 1
        commit_hash = (self.last_commit = git("rev-parse", "HEAD~#{commits}", backup_command: ['rev-list', '--max-parents=0', 'HEAD']))
      end

      commit_hash
    end

    def last_commit=(v)
      PluginStore.set(DiscourseCodeReview::PluginName, LastCommit + @name, v)
      v
    end

    def commit_hash_valid?(hash)
      git("cat-file", "-t", hash) == "commit"
    rescue
      false
    end

    def master_contains?(ref)
      git('pull')

      hash = git('rev-parse', ref)
      git('merge-base', 'origin/master', hash) == hash
    end

    def commit_comments(commit_sha)
      git("pull")

      octokit_client.commit_comments(@name, commit_sha).map do |hash|
        line_content = nil

        if hash[:path].present? && hash[:position].present?
          diff = git("diff", "#{hash[:commit_id]}~1", hash[:commit_id], hash[:path], raise_error: false)
          if diff.present?
            # 5 is preamble
            start = [hash[:position] + 5 - 3, 5].max
            finish = hash[:position] + 5 + 3
            line_content = diff.split("\n")[start..finish].join("\n")
          end
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
          line_content: line_content
        }
      end
    end

    def commit(hash)
      git("pull")
      begin
        git("log", "-1", hash, warn: false)
        commits_since(hash, single: true, pull: false).first
      rescue StandardError
        nil
      end
    end

    def commits_since(hash = nil, merge_github_info: true, pull: true, single: false)
      if pull
        git("pull")
      end

      hash ||= last_commit

      github_info = []

      range = single ? ["-1", hash] : ["#{hash}.."]

      commits = git("log", *range, "--pretty=%H").split("\n").map { |x| x.strip }

      if merge_github_info
        commits.each_slice(30).each do |x|
          github_commits = octokit_client.commits(@name, sha: x.first)
          github_info.concat(github_commits)
        end
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
      format = %w{%H %aN %aE %s %B %at}.join(FIELD_END) << LINE_END

      data = git("log", *range, "--pretty=#{format}")

      data.split(LINE_END).map do |line|
        fields = line.split(FIELD_END).map { |f| f.strip if f }

        hash = fields[0].strip

        body = fields[4] || ''

        diff = git("show", "--format=%b", hash)

        if diff.present?
          diff_lines = diff[0..MAX_DIFF_LENGTH + body.length]
            .strip
            .split("\n")

          while diff_lines[0] && !diff_lines[0].start_with?("diff --git")
            diff_lines.delete_at(0)
          end

          truncated = diff.length > (MAX_DIFF_LENGTH + body.length)
          if truncated
            diff_lines.delete_at(diff_lines.length - 1)
          end

          diff = diff_lines.join("\n")
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
          diff_truncated: truncated
        }.merge(github_data)

      end.reverse

    end

    def path
      @path ||= (Rails.root + "tmp/code-review-repo/#{clean_name}").to_s
    end

    # for testing
    def path=(v)
      @path = v
    end

    def clone(path)
      github_token = SiteSetting.code_review_github_token

      url =
        if (SiteSetting.code_review_allow_private_clone && github_token.present?)
          "https://#{github_token}@github.com/#{@name}.git"
        else
          "https://github.com/#{@name}.git"
        end
      `git clone #{url} '#{path}'`
    end

    def git(*command, backup_command: [], raise_error: true, warn: true)
      FileUtils.mkdir_p(Rails.root + "tmp/code-review-repo")

      if !File.exist?(path)
        clone(path)
        if $?.exitstatus != 0
          raise StandardError, "Failed to clone repo #{@name} in tmp/code-review-repo"
        end
      end

      Dir.chdir(path) do
        last_command = command
        last_error = nil
        begin
          result = Discourse::Utils.execute_command('git', *command).strip
        rescue RuntimeError => e
          last_error = e
        end

        if result.nil?
          unless backup_command.empty?
            last_command = backup_command
            begin
              result = Discourse::Utils.execute_command('git', *backup_command).strip
            rescue RuntimeError => e
              last_error = e
            end
          end

          if result.nil?
            if warn
              Rails.logger.warn("Discourse Code Review: Failed to run `#{last_command.join(' ')}` in #{path} with error: #{last_error}")
            end

            if raise_error
              raise StandardError, "Failed to run git command #{last_command.join(' ')} on #{@name} in tmp/code-review-repo"
            end
          end
        end
        result
      end

    end

  end
end
