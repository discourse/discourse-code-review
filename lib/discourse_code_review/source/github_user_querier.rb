# frozen_string_literal: true

module DiscourseCodeReview::Source
  class GithubUserQuerier
    def initialize(client)
      @client = client
    end

    def get_user_email(github_login)
      client.user(github_login)[:email]
    end

    private

    attr_reader :client
  end
end
