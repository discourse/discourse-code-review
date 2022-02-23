# frozen_string_literal: true

module RemoteMocks
  class << self
    include Helpers

    def repos
      @repos ||= []
    end

    def make_repo
      path = setup_git_repo({})
      repos << path
      Rugged::Repository.new(path)
    end

    def cleanup!
      repos.each do |path|
        FileUtils.rm_rf(path)
      end
    end
  end
end
