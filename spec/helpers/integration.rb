# frozen_string_literal: true

require_relative 'remote_mocks'
require_relative 'graphql_client_mock'
require_relative 'rugged_interceptor'
require_relative 'github_rest_api_mock'

module CodeReviewIntegrationHelpers
  def declare_github_repo!(owner:, repo:, default_branch: "master", &blk)
    local = RemoteMocks.make_repo

    RuggedInterceptor::Repository.intercept(
      "https://github.com/#{owner}/#{repo}.git",
      local.workdir,
    )

    GithubRestAPIMock.declare_repo!(
      owner: owner,
      repo: repo,
      default_branch: default_branch
    )

    blk.call(local)
  end

  def declare_github_commit_comment!(**kwargs)
    GithubRestAPIMock.declare_commit_comment!(**kwargs)
  end
end

RSpec.configure do |config|
  config.include CodeReviewIntegrationHelpers

  config.before(:each, type: :code_review_integration) do
    DiscourseCodeReview.reset_state!

    DiscourseCodeReview
      .stubs(:graphql_client)
      .returns(GraphQLClientMock.new)

    FileUtils.rm_rf('tmp/code-review-repo/')

    GithubRestAPIMock.setup!
  end

  config.around(type: :code_review_integration) do |example|
    RuggedInterceptor.use do
      example.run
    end
  end

  config.after(type: :code_review_integration) do
    RemoteMocks.cleanup!
  end
end
