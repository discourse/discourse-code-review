# frozen_string_literal: true

module RemoteMocks
  class << self
    def repos
      @repos ||= []
    end

    def make_repo
      path = "/tmp/#{SecureRandom.hex}"
      repos << path
      Rugged::Repository.init_at(path)
    end

    def cleanup!
      repos.each do |path|
        FileUtils.rm_rf(path)
      end
    end
  end
end
