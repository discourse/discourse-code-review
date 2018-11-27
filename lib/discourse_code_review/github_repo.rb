# frozen_string_literal: true

module DiscourseCodeReview
  class GithubRepo

    attr_reader :name, :octokit_client

    LastCommit = 'last commit'
    CommentPage = 'comment page'

    LINE_END = "52fc72dfa9cafa9da5e6266810b884ae"
    FEILD_END = "52fc72dfa9cafa9da5e6266810b884ff"

    MAX_DIFF_LENGTH = 8000

    def initialize(name, octokit_client)
      @name = name
      @octokit_client = octokit_client
    end

    def current_comment_page
      (PluginStore.get(DiscourseCodeReview::PluginName, CommentPage + @name) || 1).to_i
    end

    def current_comment_page=(v)
      PluginStore.set(DiscourseCodeReview::PluginName, CommentPage + @name, v)
      v
    end

    def clean_name
      @name.gsub(/[^a-z0-9]/i, "_")
    end

    def last_commit
      PluginStore.get(DiscourseCodeReview::PluginName, LastCommit + @name) ||
        (self.last_commit = git('rev-parse HEAD~30', backup_command: 'rev-list --max-parents=0 HEAD'))
    end

    def last_commit=(v)
      PluginStore.set(DiscourseCodeReview::PluginName, LastCommit + @name, v)
      v
    end

    def commit_comments(page = nil)
      # TODO add a distributed lock here
      git("checkout -f master")
      git("pull")

      page ||= current_comment_page

      octokit_client.list_commit_comments(@name, page: page).map do |hash|

        line_content = nil

        if hash[:path].present? && hash[:position].present?

          git("checkout -f #{hash[:commit_id]}", raise_error: false)
          if !File.exist?("#{path}#{hash[:path]}")
            git("checkout -f #{hash[:commit_id]}~1", raise_error: false)
          end

          diff = ""
          if !File.exist?("#{path}#{hash[:path]}")
            diff = git("diff #{hash[:commit_id]}~1 #{hash[:commit_id]} #{hash[:path]}", raise_error: false)
          end

          git("checkout -f master", raise_error: false)

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

    def commits_since(hash = nil)
      git("checkout -f master")
      git("pull")

      hash ||= last_commit

      github_info = []

      commits = git("log #{hash}.. --pretty=%H").split("\n").map { |x| x.strip }

      commits.each_slice(30).each do |x|
        commits = octokit_client.commits(@name, sha: x.first)
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

    def path
      @path ||= (Rails.root + "tmp/code-review-repo/#{clean_name}").to_s
    end

    def git(command, backup_command: nil, raise_error: true)
      FileUtils.mkdir_p(Rails.root + "tmp/code-review-repo")

      if !File.exist?(path)
        `git clone https://github.com/#{@name}.git '#{path}'`
        if $?.exitstatus != 0
          raise StandardError, "Failed to clone repo #{@name} in tmp/code-review-repo"
        end
      end

      Dir.chdir(path) do
        result = `git #{command}`.strip
        if $?.exitstatus != 0
          if backup_command
            result = `git #{backup_command}`.strip
          end

          if $?.exitstatus != 0
            Rails.logger.warn("Discourse Code Review: Failed to run `#{command}` in #{path} error code: #{$?}")

            if raise_error
              raise StandardError, "Failed to run git command #{command} on #{@name} in tmp/code-review-repo"
            end
          end
        end
        result
      end

    end

  end
end
