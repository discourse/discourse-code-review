# frozen_string_literal: true

module Jobs
  class CodeReviewSyncPullRequest < ::Jobs::Base
    def execute(args)
      repo_name, issue_number, repo_id = args.values_at(:repo_name, :issue_number, :repo_id)

      unless repo_name.kind_of?(String)
        raise Discourse::InvalidParameters.new(:repo_name)
      end

      syncer = DiscourseCodeReview.github_pr_syncer
      syncer.sync_pull_request(repo_name, issue_number, repo_id: repo_id)
    end
  end
end
