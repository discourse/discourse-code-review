# frozen_string_literal: true

class DiscourseCodeReview::SkippedCodeReview < ActiveRecord::Base
  self.table_name = 'skipped_code_reviews'
  belongs_to :user
  belongs_to :topic
end
