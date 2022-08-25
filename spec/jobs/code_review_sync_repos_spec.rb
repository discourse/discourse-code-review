# frozen_string_literal: true

require 'rails_helper'
require_relative '../helpers/integration'

describe Jobs::CodeReviewSyncRepos, type: :code_review_integration do
  before do
    SiteSetting.code_review_github_token = 'code_review_github_token'

    declare_github_repo!(
      owner: 'discourse',
      repo: 'discourse-code-review',
      default_branch: 'main',
      last_commit: 'abcdef',
    ) do |repo|
      msg = 'Initial commit'

      Dir.chdir(repo.workdir) do
        File.write('README.md', <<~EOF)
          Just store text files with your todo list items.
        EOF

        `git add README.md`
        `git commit -m 'Initial commit'`
        `git branch -m main`

        commit = `git rev-parse HEAD`
      end
    end
  end

  it 'schedules sync jobs for outdated repos' do
    DiscourseCodeReview::State::GithubRepoCategories.ensure_category(repo_name: 'discourse/discourse-code-review', repo_id: 42)

    expect { described_class.new.execute }
      .to change { Jobs::CodeReviewSyncCommits.jobs.count }.by(1)
  end

  it 'does not schedule sync jobs for updated repos' do
    DiscourseCodeReview::State::GithubRepoCategories.ensure_category(repo_name: 'discourse/discourse-code-review', repo_id: 42)
    PluginStore.set(DiscourseCodeReview::PluginName, DiscourseCodeReview::GithubRepo::LAST_COMMIT + 'discourse/discourse-code-review', 'abcdef')

    expect { described_class.new.execute }
      .to change { Jobs::CodeReviewSyncCommits.jobs.count }.by(0)
  end
end
