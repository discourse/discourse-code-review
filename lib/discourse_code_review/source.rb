# frozen_string_literal: true

# Some things are simple, because they don't touch the DB.
#
# They belong here.

module DiscourseCodeReview::Source
end

require File.expand_path("../source/git_repo", __FILE__)
require File.expand_path("../source/github_pr_service", __FILE__)
require File.expand_path("../source/github_pr_querier", __FILE__)
require File.expand_path("../source/github_user_querier", __FILE__)
require File.expand_path("../source/commit_querier.rb", __FILE__)
