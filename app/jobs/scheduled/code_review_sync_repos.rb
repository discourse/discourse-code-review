# frozen_string_literal: true

module Jobs
  class CodeReviewSyncRepos < ::Jobs::Scheduled
    every 1.hour

    def execute(args = {})
      client = DiscourseCodeReview.octokit_bot_client
      github_commit_querier = DiscourseCodeReview.github_commit_querier

      DiscourseCodeReview::State::GithubRepoCategories.each_repo_name do |repo_name|
        github_repo = DiscourseCodeReview::GithubRepo.new(repo_name, client, github_commit_querier)
        octokit_repo = client.repository(repo_name)
        branch = client.branch(repo_name, octokit_repo.default_branch)

        last_local_commit = github_repo.last_local_commit
        last_remote_commit = branch.commit.sha

        if last_local_commit != last_remote_commit
          ::Jobs.enqueue(:code_review_sync_commits, repo_name: repo_name)
        end
      end
    end
  end
end
