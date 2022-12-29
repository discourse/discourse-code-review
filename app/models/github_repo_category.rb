# frozen_string_literal: true

class DiscourseCodeReview::GithubRepoCategory < ActiveRecord::Base
  self.table_name = "code_review_github_repos"
  belongs_to :category

  # "Moved" indicates that the repo has either been transferred or renamed.
  #
  scope :not_moved, -> { where.not(repo_id: nil) }
end
