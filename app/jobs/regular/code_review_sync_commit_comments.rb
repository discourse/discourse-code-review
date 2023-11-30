# frozen_string_literal: true

module Jobs
  class CodeReviewSyncCommitComments < ::Jobs::Base
    include OctokitRateLimitRetryMixin

    sidekiq_options queue: "low"

    def execute(args)
      repo_name, commit_sha, repo_id = args.values_at(:repo_name, :commit_sha, :repo_id)

      raise Discourse::InvalidParameters.new(:repo_name) unless repo_name.kind_of?(String)

      raise Discourse::InvalidParameters.new(:commit_sha) unless commit_sha.kind_of?(String)

      client = DiscourseCodeReview.octokit_client
      github_commit_querier = DiscourseCodeReview.github_commit_querier
      repo =
        DiscourseCodeReview::GithubRepo.new(
          repo_name,
          client,
          github_commit_querier,
          repo_id: repo_id,
        )

      importer = DiscourseCodeReview::Importer.new(repo)
      importer.sync_commit_sha(commit_sha)

      syncer = DiscourseCodeReview.github_pr_syncer
      syncer.sync_associated_pull_requests(repo_name, commit_sha, repo_id: repo_id)
    end
  end
end
