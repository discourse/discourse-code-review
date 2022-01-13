# frozen_string_literal: true

class DiscourseCodeReview::CommitTopic < ActiveRecord::Base
  self.table_name = 'code_review_commit_topics'
  belongs_to :topic
end
