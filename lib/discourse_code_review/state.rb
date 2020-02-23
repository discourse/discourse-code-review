# frozen_string_literal: true

module DiscourseCodeReview::State; end

# Some things are simple, because they only exist to manipulate data in the DB.
#
# They belong here

require File.expand_path("../state/commit_approval", __FILE__)
require File.expand_path("../state/github_repo_categories.rb", __FILE__)
