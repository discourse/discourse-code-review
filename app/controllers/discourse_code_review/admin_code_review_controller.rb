# frozen_string_literal: true

module DiscourseCodeReview
  class AdminCodeReviewController < ::ApplicationController
    requires_plugin DiscourseCodeReview::PLUGIN_NAME

    def index
    end
  end
end
