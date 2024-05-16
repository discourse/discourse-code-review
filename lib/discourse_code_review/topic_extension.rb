# frozen_string_literal: true

module DiscourseCodeReview
  module TopicExtension
    extend ActiveSupport::Concern

    prepended { has_one :code_review_commit_topic, class_name: "DiscourseCodeReview::CommitTopic" }
  end
end
