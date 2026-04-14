# frozen_string_literal: true

module DiscourseCodeReview
  describe GithubRepo do
    def with_tmpdir(&blk)
      path = "#{Pathname.new(Dir.tmpdir).realpath}/#{SecureRandom.hex}"
      begin
        blk.call(path)
      ensure
        FileUtils.rm_rf(path)
      end
    end

    attr_reader :checkout_path
    attr_reader :origin_path

    around(:each) do |example|
      with_tmpdir do |checkout_path|
        @checkout_path = checkout_path
        @origin_path = setup_git_repo({})

        DiscourseCodeReview::Source::GitRepo.new(origin_path, checkout_path)

        Dir.chdir(checkout_path) { example.run }
      end
    end

    context "with a merge commit" do
      before do
        Dir.chdir(origin_path) do
          File.write("a", "hello worlds\n")
          `git add a`
          `git commit -am 'first commit'`

          `git checkout -q -b test`
          File.write("b", "test")
          `git add b`
          `git commit -am testing`
          `git checkout -q main`

          File.write("a", "hello world\n")
          `git commit -am 'second commit'`

          `git merge test`
        end
      end

      it "does not explode" do
        repo = GithubRepo.new("fake_repo/fake_repo", nil, nil, repo_id: 24)
        repo.stubs(:default_branch).returns("origin/main")
        repo.path = checkout_path
        repo.last_commit = nil

        commits = repo.commits_since("origin/main~2", merge_github_info: false)

        expect(commits.last[:diff]).to eq("MERGE COMMIT")
      end
    end

    context "with a commit with a long diff" do
      before do
        Dir.chdir(origin_path) do
          File.write("a", "Hello, world!\n" * 1000)
          `git add a`
          `git commit -am 'first commit'`
          File.write("a", "hello2")
          `git commit -am 'second commit\n\nline 2'`
        end
      end

      it "truncates the diff" do
        repo = GithubRepo.new("fake_repo/fake_repo", nil, nil, repo_id: 24)
        repo.stubs(:default_branch).returns("origin/main")
        repo.path = checkout_path
        repo.last_commit = nil

        last_commit = repo.commits_since(nil, merge_github_info: false).last
        diff = last_commit[:diff]

        expect(last_commit[:diff_truncated]).to eq(true)
        expect(diff).to ending_with("Hello, world!")

        # no point repeating the message
        expect(diff).not_to include("second commit")
        expect(diff).not_to include("line 2")
      end
    end

    it "can respect catchup commits" do
      sha = nil

      Dir.chdir(origin_path) do
        File.write("a", "hello")
        `git add a`
        `git commit -am 'first commit'`
        File.write("a", "hello2")
        `git commit -am 'second commit'`
        File.write("a", "hello3")
        `git commit -am 'third commit'`

        sha = `git rev-parse HEAD`.strip
      end

      repo = GithubRepo.new("fake_repo/fake_repo", nil, nil, repo_id: 24)
      repo.stubs(:default_branch).returns("origin/main")
      repo.path = checkout_path

      SiteSetting.code_review_catch_up_commits = 1

      expect(repo.last_commit).to eq(sha)
    end

    it "does not explode on force pushing (bad hash)" do
      sha = nil

      Dir.chdir(origin_path) do
        File.write("a", "hello")
        `git add a`
        `git commit -am 'first commit'`
        File.write("a", "hello2")
        `git commit -am 'second commit'`

        sha = `git rev-parse HEAD`.strip
      end

      repo = GithubRepo.new("fake_repo/fake_repo", nil, nil, repo_id: 24)
      repo.stubs(:default_branch).returns("origin/main")
      repo.path = checkout_path

      # mimic force push event
      repo.last_commit = "98ab71e61d89149bac528e1d01b9c6d17e5f677a"

      SiteSetting.code_review_catch_up_commits = 1

      expect(repo.last_commit).to eq(sha)
    end

    it "can get the diff of the first commit" do
      sha = nil

      Dir.chdir(origin_path) do
        File.write("a", "hello")
        `git add a`
        `git commit -am 'first commit'`
        File.write("a", "hello2")
        `git commit -am 'second commit'`
        File.write("a", "hello3")
        `git commit -am 'third commit'`

        sha = `git rev-list --max-parents=0 HEAD`.strip
      end

      repo = GithubRepo.new("fake_repo/fake_repo", nil, nil, repo_id: 24)
      repo.stubs(:default_branch).returns("origin/main")
      repo.path = checkout_path
      repo.git_repo.fetch

      expect(repo.git_repo.diff_excerpt(sha, "a", 0)).to eq <<~DIFF.strip
        @@ -0,0 +1 @@
        +hello
        \\ No newline at end of file
      DIFF
    end
  end
end
