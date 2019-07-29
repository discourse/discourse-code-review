# frozen_string_literal: true

module DiscourseCodeReview
  class OrganizationsController < ::ApplicationController
    def index
      render_json_dump(DiscourseCodeReview.github_organizations)
    end
  end
end
