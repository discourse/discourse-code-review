# frozen_string_literal: true

module Jobs
  class CodeReviewSyncCommits < ::Jobs::Base
    def execute(args)
      unless args[:repo_name].kind_of?(String)
        raise Discourse::InvalidParameters.new(:repo_name)
      end

      repo_name, repo_id = args.values_at(:repo_name, :repo_id)

      client = DiscourseCodeReview.octokit_client
      github_commit_querier = DiscourseCodeReview.github_commit_querier

      repo = DiscourseCodeReview::GithubRepo.new(repo_name, client, github_commit_querier, repo_id: repo_id)
      importer = DiscourseCodeReview::Importer.new(repo)

      importer.sync_merged_commits do |commit_hash|
        if SiteSetting.code_review_approve_approved_prs
          Rails.logger.warn("[Jobs::CodeReviewSyncCommits] Applying Github approves for repo_name = #{repo_name}, commit_hash = #{commit_hash}") if SiteSetting.code_review_debug
          DiscourseCodeReview
            .github_pr_syncer
            .apply_github_approves(repo_name, commit_hash)
        end
      end
    end
  end
end
