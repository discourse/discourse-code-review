# frozen_string_literal: true

module Jobs
  class CodeReviewSyncRepos < ::Jobs::Scheduled
    every 1.hour

    def execute(args = {})
      DiscourseCodeReview::GithubRepoCategory
        .not_moved
        .pluck(:name, :repo_id)
        .each do |repo_name, repo_id|
          ::Jobs.enqueue(
            :code_review_sync_commits,
            repo_name: repo_name,
            repo_id: repo_id,
            skip_if_up_to_date: true,
          )
        end
    end
  end
end
