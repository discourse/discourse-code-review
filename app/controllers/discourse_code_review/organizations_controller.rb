# frozen_string_literal: true

module DiscourseCodeReview
  class OrganizationsController < ::ApplicationController
    requires_plugin DiscourseCodeReview::PLUGIN_NAME

    def index
      render_json_dump(DiscourseCodeReview.github_organizations)
    end
  end
end
