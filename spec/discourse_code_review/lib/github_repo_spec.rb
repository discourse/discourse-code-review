require 'rails_helper'

module DiscourseCodeReview
  describe GithubRepo do

    before do
      @git_path = "#{Pathname.new(Dir.tmpdir).realpath}/#{SecureRandom.hex}"
      FileUtils.mkdir @git_path
    end

    after do
      FileUtils.rm_rf(@git_path)
    end

    it "can respect catchup commits" do
      Dir.chdir(@git_path) do
        `git init .`
        File.write('a', 'hello')
        `git add a`
        `git commit -am 'first commit'`
        File.write('a', 'hello2')
        `git commit -am 'second commit'`
        File.write('a', 'hello3')
        `git commit -am 'third commit'`

        repo = GithubRepo.new('fake_repo/fake_repo', nil)
        repo.path = @git_path

        SiteSetting.code_review_catch_up_commits = 1

        sha = `git rev-parse HEAD~0`.strip

        expect(repo.last_commit).to eq(sha)
      end
    end
  end
end
