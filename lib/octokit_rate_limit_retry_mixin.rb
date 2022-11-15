# frozen_string_literal: true

module OctokitRateLimitRetryMixin
  def self.included(base)
    base.sidekiq_retry_in do |count, exception|
      case exception&.wrapped
      when Octokit::TooManyRequests
        rate_limit = DiscourseCodeReview.octokit_client.rate_limit
        rand(rate_limit.resets_in..(rate_limit.resets_in + 60))
      else
        # Retry only once in 30..90 seconds
        count == 0 ? rand(30..90) : :discard
      end
    end
  end
end
