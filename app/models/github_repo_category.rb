# frozen_string_literal: true

class DiscourseCodeReview::GithubRepoCategory < ActiveRecord::Base
  self.table_name = 'code_review_github_repos'
  belongs_to :category
end
