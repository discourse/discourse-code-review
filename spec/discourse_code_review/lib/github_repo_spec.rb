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

    it "does not explode with merge commits" do

      Dir.chdir(@git_path) do
        `git init .`
        File.write('a', "hello worlds\n")
        `git add a`
        `git commit -am 'first commit'`

        `git branch test`
        `git checkout test`
        File.write('b', 'test')
        `git add b`
        `git commit -am testing`
        `git checkout master`

        File.write('a', "hello world\n")
        `git commit -am 'second commit'`

        `git merge test`

        repo = GithubRepo.new('fake_repo/fake_repo', nil)

        repo.path = @git_path
        repo.last_commit = nil

        commits = repo.commits_since("HEAD~2", merge_github_info: false, pull: false)

        expect(commits.last[:diff]).to eq("")
      end
    end

    it "can cleanly truncate diffs" do
      Dir.chdir(@git_path) do
        `git init .`
        File.write('a', "hello world\n" * 1000)
        `git add a`
        `git commit -am 'first commit'`
        File.write('a', 'hello2')
        `git commit -am 'second commit\n\nline 2'`

        repo = GithubRepo.new('fake_repo/fake_repo', nil)

        repo.path = @git_path
        repo.last_commit = nil

        last_commit = repo.commits_since(nil, merge_github_info: false, pull: false).last
        diff = last_commit[:diff]

        expect(last_commit[:diff_truncated]).to eq(true)
        expect(diff).to ending_with("hello world")

        # no point repeating the message
        expect(diff).not_to include("second commit")
        expect(diff).not_to include("line 2")
      end
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

    it "does not explode on force pushing (bad hash)" do
      Dir.chdir(@git_path) do
        `git init .`
        File.write('a', 'hello')
        `git add a`
        `git commit -am 'first commit'`
        File.write('a', 'hello2')
        `git commit -am 'second commit'`

        repo = GithubRepo.new('fake_repo/fake_repo', nil)
        repo.path = @git_path

        # mimic force push event
        repo.last_commit = "98ab71e61d89149bac528e1d01b9c6d17e5f677a"

        File.write('a', 'hello3')
        `git commit -am 'third commit'`

        SiteSetting.code_review_catch_up_commits = 1

        sha = `git rev-parse HEAD~0`.strip
        expect(repo.last_commit).to eq(sha)
      end
    end
  end
end
