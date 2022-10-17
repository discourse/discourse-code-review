# frozen_string_literal: true

module Jobs
  class CodeReviewSyncCommits < ::Jobs::Base
    sidekiq_options retry: false

    def execute(args)
      unless args[:repo_name].kind_of?(String)
        raise Discourse::InvalidParameters.new(:repo_name)
      end

      repo_name, repo_id = args.values_at(:repo_name, :repo_id)

      octokit_client = DiscourseCodeReview.octokit_client
      github_commit_querier = DiscourseCodeReview.github_commit_querier
      graphql_client = DiscourseCodeReview.graphql_client

      repo = DiscourseCodeReview::GithubRepo.new(repo_name, octokit_client, github_commit_querier, repo_id: repo_id)

      if args[:skip_if_up_to_date]
        begin
          owner, name = repo_name.split('/')
          response = graphql_client.execute <<~GRAPHQL
            query {
              repo: repository(owner: \"#{owner}\", name: \"#{name}\") {
                defaultBranchRef {
                  target {
                    oid
                  }
                }
              }
            }
          GRAPHQL
          last_remote_commit = response.dig(:repo, :defaultBranchRef, :target, :oid)
        rescue
          Rails.logger.warn("Cannot fetch GitHub repo information for #{repo_name}")
        end

        return if repo.last_local_commit == last_remote_commit
      end

      importer = DiscourseCodeReview::Importer.new(repo)

      importer.sync_merged_commits do |commit_hash|
        if SiteSetting.code_review_approve_approved_prs
          Rails.logger.warn("[DiscourseCodeReview] [Jobs::CodeReviewSyncCommits] Applying Github approves for repo_name = #{repo_name}, commit_hash = #{commit_hash}") if SiteSetting.code_review_debug
          DiscourseCodeReview
            .github_pr_syncer
            .apply_github_approves(repo_name, commit_hash)
        end
      end
    end
  end
end
