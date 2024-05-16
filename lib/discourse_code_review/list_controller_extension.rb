# frozen_string_literal: true

module DiscourseCodeReview
  module ListControllerExtension
    extend ActiveSupport::Concern

    prepended { skip_before_action :ensure_logged_in, only: %i[approval_given approval_pending] }
  end
end
