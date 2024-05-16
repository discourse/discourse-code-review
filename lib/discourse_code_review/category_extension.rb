# frozen_string_literal: true

module DiscourseCodeReview
  module CategoryExtension
    extend ActiveSupport::Concern

    prepended do
      has_one :github_repo_category,
              class_name: "DiscourseCodeReview::GithubRepoCategory",
              dependent: :destroy
    end
  end
end
