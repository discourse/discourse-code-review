# frozen_string_literal: true

module GithubRestAPIMock
  REPO_REQUEST = %r{https://api.github.com/repos/([^/]+)/([^/]+)}
  COMMENTS_REQUEST = %r{https://api.github.com/repos/([^/]+)/([^/]+)/commits/([^/]+)/comments}

  class << self
    def infos
      @infos ||= {}
    end

    def comments
      @comments ||=
        Hash.new { |comments, owner_repo| comments[owner_repo] = Hash.new { |h, sha| h[sha] = [] } }
    end

    def declare_repo!(owner:, repo:, default_branch:)
      infos[[owner, repo]] = { default_branch: default_branch }
    end

    def declare_commit_comment!(owner:, repo:, commit:, comment:)
      comments[[owner, repo]][commit] << comment
    end

    def setup!
      stub_request(:get, REPO_REQUEST) do |match|
        _, owner, repo = match.to_a

        {
          headers: {
            "Content-Type": "application/json",
          },
          body: infos.fetch([owner, repo]).to_json,
        }
      end

      stub_request(:get, COMMENTS_REQUEST) do |match|
        _, owner, repo, sha = match.to_a

        {
          headers: {
            "Content-Type": "application/json",
          },
          body: comments[[owner, repo]][sha].to_json,
        }
      end
    end

    private

    def stub_request(method, regex, &blk)
      WebMock
        .stub_request(:get, regex)
        .to_return do |request|
          matches =
            WebMock::Util::URI
              .variations_of_uri_as_strings(request.uri)
              .flat_map { |uri| [regex.match(uri)].compact }

          raise unless matches.size == 1
          match = matches.first

          blk.call(match)
        end
    end
  end
end
