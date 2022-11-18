# frozen_string_literal: true

require 'rails_helper'

describe OctokitRateLimitRetryMixin do
  describe 'sidekiq_retry_in' do
    class TestJob < ::Jobs::Base
      include OctokitRateLimitRetryMixin
    end

    let(:exception) { Jobs::HandledExceptionWrapper.new(Octokit::TooManyRequests.new) }

    before do
      stub_request(:get, "https://api.github.com/rate_limit")
        .to_return(status: 200, body: "", headers: {
          "X-RateLimit-Limit" => 1000,
          "X-RateLimit-Remaining" => 0,
          "X-RateLimit-Reset" => 90.minutes.from_now.to_i,
          "X-RateLimit-Resource" => "core",
          "X-RateLimit-Used" => 0,
        })
    end

    it 'retries after rate limit expires' do
      expect(TestJob.sidekiq_retry_in_block.call(0, exception)).to be >= 3600
    end

    it 'retries after rate limit expires again' do
      expect(TestJob.sidekiq_retry_in_block.call(1, exception)).to be >= 3600
    end

    it 'retries once for other errors' do
      expect(TestJob.sidekiq_retry_in_block.call(0, nil)).to be >= 30
      expect(TestJob.sidekiq_retry_in_block.call(0, nil)).to be <= 90
      expect(TestJob.sidekiq_retry_in_block.call(1, nil)).to eq(:discard)
    end
  end
end
