# frozen_string_literal: true

module Jobs
  class CodeReviewSyncPullRequest < ::Jobs::Base
    include OctokitRateLimitRetryMixin

    sidekiq_options queue: "low"

    def execute(args)
      repo_name, issue_number, repo_id = args.values_at(:repo_name, :issue_number, :repo_id)

      raise Discourse::InvalidParameters.new(:repo_name) unless repo_name.kind_of?(String)

      syncer = DiscourseCodeReview.github_pr_syncer
      syncer.sync_pull_request(repo_name, issue_number, repo_id: repo_id)
    end
  end
end
