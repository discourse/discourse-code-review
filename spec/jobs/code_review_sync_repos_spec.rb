# frozen_string_literal: true

require 'rails_helper'
require_relative '../helpers/integration'

describe Jobs::CodeReviewSyncRepos, type: :code_review_integration do
  it "schedules sync jobs for all repos" do
    DiscourseCodeReview::State::GithubRepoCategories.ensure_category(repo_name: "discourse", repo_id: 42)
    DiscourseCodeReview::State::GithubRepoCategories.ensure_category(repo_name: "discourse-code-review", repo_id: 43)

    expect { described_class.new.execute }
      .to change { Jobs::CodeReviewSyncCommits.jobs.count }.by(2)
  end
end
