# frozen_string_literal: true

require 'rails_helper'
require_relative '../helpers/integration'

describe Jobs::CodeReviewSyncCommits, type: :code_review_integration do
  context "with a fake github repo" do
    before do
      commit = nil
      declare_github_repo!(
        owner: "10xninjarockstar",
        repo: "ultimatetodolist",
        default_branch: "main",
        last_commit: "abcdef",
      ) do |repo|
        msg = "Initial commit"

        Dir.chdir(repo.workdir) do
          File.write("README.md", <<~EOF)
            Just store text files with your todo list items.
          EOF

          `git add README.md`
          `git commit -m "Initial commit"`
          `git branch -m main`

          commit = `git rev-parse HEAD`
        end
      end

      declare_github_commit_comment!(
        owner: "10xninjarockstar",
        repo: "ultimatetodolist",
        commit: commit,
        comment: {}
      )
    end

    it "creates a commit topic and a category topic, with a full sha in the first post" do
      expect {
        described_class.new.execute(repo_name: '10xninjarockstar/ultimatetodolist', repo_id: 24)
      }.to change { Topic.count }.by(2)

      topics = Topic.order('id desc').limit(2)

      commit_post = topics.first.first_post

      hash = topics.first.custom_fields[DiscourseCodeReview::COMMIT_HASH]
      expect(commit_post.raw).to include("sha: #{hash}")
    end

    it "skips if last local and remote commit SHAs match" do
      PluginStore.set(
        DiscourseCodeReview::PluginName,
        DiscourseCodeReview::GithubRepo::LAST_COMMIT + '10xninjarockstar/ultimatetodolist',
        'abcdef'
      )

      expect {
        described_class.new.execute(repo_name: '10xninjarockstar/ultimatetodolist', repo_id: 24, skip_if_up_to_date: true)
      }.to change { Topic.count }.by(0)
    end

    it "does not skips if last local and remote commit SHAs mismatch" do
      PluginStore.set(
        DiscourseCodeReview::PluginName,
        DiscourseCodeReview::GithubRepo::LAST_COMMIT + '10xninjarockstar/ultimatetodolist',
        'abcdeg'
      )

      expect {
        described_class.new.execute(repo_name: '10xninjarockstar/ultimatetodolist', repo_id: 24, skip_if_up_to_date: true)
      }.to change { Topic.count }.by(2)
    end
  end
end
