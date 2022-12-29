# frozen_string_literal: true

module DiscourseCodeReview
  class Importer
    attr_reader :github_repo

    def initialize(github_repo)
      @github_repo = github_repo
    end

    def self.sync_commit(sha)
      client = DiscourseCodeReview.octokit_client
      github_commit_querier = DiscourseCodeReview.github_commit_querier

      State::GithubRepoCategories.each_repo_name do |repo_name|
        repo = GithubRepo.new(repo_name, client, github_commit_querier)
        importer = Importer.new(repo)

        if commit = repo.commit(sha)
          importer.sync_commit(commit)
          return repo_name
        end
      end

      nil
    end

    def self.sync_commit_from_repo(repo_name, sha)
      client = DiscourseCodeReview.octokit_client
      github_commit_querier = DiscourseCodeReview.github_commit_querier
      repo = GithubRepo.new(repo_name, client, github_commit_querier)
      importer = Importer.new(repo)
      importer.sync_commit_sha(sha)
    end

    def category_id
      @category_id ||=
        State::GithubRepoCategories.ensure_category(
          repo_name: github_repo.name,
          repo_id: github_repo.repo_id,
        ).id
    end

    def sync_merged_commits
      last_commit = nil
      github_repo.commits_since.each do |commit|
        sync_commit(commit)

        yield commit[:hash] if block_given?

        github_repo.last_commit = commit[:hash]
      end
    end

    def sync_commit_sha(commit_sha)
      commit = github_repo.commit(commit_sha)
      return if commit.nil?
      sync_commit(commit)
    end

    def sync_commit(commit)
      topic_id = import_commit(commit)
      import_comments(topic_id, commit[:hash])
      topic_id
    end

    def import_commit(commit)
      merged = github_repo.default_branch_contains?(commit[:hash])
      followees = github_repo.followees(commit[:hash])

      user =
        DiscourseCodeReview.github_user_syncer.ensure_user(
          email: commit[:email],
          name: commit[:name],
          github_login: commit[:author_login],
          github_id: commit[:author_id],
        )

      State::CommitTopics.ensure_commit(
        category_id: category_id,
        commit: commit,
        merged: merged,
        repo_name: github_repo.name,
        user: user,
        followees: followees,
      )
    end

    def import_comments(topic_id, commit_sha)
      github_repo
        .commit_comments(commit_sha)
        .each do |comment|
          login = comment[:login] || "unknown"
          user =
            DiscourseCodeReview.github_user_syncer.ensure_user(name: login, github_login: login)

          State::CommitTopics.ensure_commit_comment(
            user: user,
            topic_id: topic_id,
            comment: comment,
          )
        end
    end
  end
end
