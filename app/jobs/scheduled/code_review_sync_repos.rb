# frozen_string_literal: true

module Jobs
  class CodeReviewSyncRepos < ::Jobs::Scheduled
    every 1.hour

    def execute(args = nil)
      DiscourseCodeReview::State::GithubRepoCategories.each_repo_name do |repo_name|
        ::Jobs.enqueue(:code_review_sync_commits, repo_name: repo_name)
      end
    end
  end
end
