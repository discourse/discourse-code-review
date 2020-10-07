# frozen_string_literal: true

require 'rails_helper'

module DiscourseCodeReview
  describe Importer do
    def first_post_of(topic_id)
      Topic.find(topic_id).posts.order(:id).first
    end

    let(:parent_category) { Fabricate(:category) }
    let(:repo) { GithubRepo.new("discourse/discourse", Octokit::Client.new, nil) }

    it "creates categories with a description" do
      category = Category.find_by(id: Importer.new(repo).category_id)

      description = I18n.t("discourse_code_review.category_description", repo_name: "discourse/discourse").strip
      expect(category.description).to include(description)
      expect(category.topic.first_post.raw).to include(description)
    end

    it "mutes categories when code_review_default_mute_new_categories is true" do
      SiteSetting.code_review_default_mute_new_categories = true

      category = Category.find_by(id: Importer.new(repo).category_id)

      expect(SiteSetting.default_categories_muted.split("|").map(&:to_i)).to include(category.id)
      expect(category.parent_category_id).to eq(nil)
    end

    it "sets parent category when code_review_default_parent_category is persent" do
      SiteSetting.code_review_default_parent_category = parent_category.id

      category = Category.find_by(id: Importer.new(repo).category_id)

      expect(SiteSetting.default_categories_muted.split("|").map(&:to_i)).not_to include(category.id)
      expect(category.parent_category_id).to eq(parent_category.id)
    end

    it "can look up a category id consistently" do
      # lets muck stuff up first ... and create a dupe category
      Category.create!(name: 'discourse', user: Discourse.system_user)

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil)
      id = Importer.new(repo).category_id

      expect(id).to be > 0
      expect(Importer.new(repo).category_id).to eq(id)
    end

    it "can cleanly associate old commits" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil)

      diff = "```\nwith a diff"

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: diff,
        hash: "a1db15feadc7951d8a2b4ae63384babd6c568ae0"
      }

      repo.expects(:master_contains?).with(commit[:hash]).returns(true)

      post = first_post_of(Importer.new(repo).import_commit(commit))

      commit[:hash] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      commit[:body] = "ab2787347ff (this is\nfollowing up on a1db15fe)"

      repo.expects(:master_contains?).with(commit[:hash]).returns(true)

      post2 = first_post_of(Importer.new(repo).import_commit(commit))

      expect(post2.cooked).to include(post.topic.url)

      expect(post.topic.posts.length).to eq(1)
    end

    it "can handle complex imports" do

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil)

      diff = "```\nwith a diff"

      body = <<~MD
      this is [amazing](http://amaz.ing)
      MD

      commit = {
        subject: "hello world",
        body: body,
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: diff,
        hash: SecureRandom.hex
      }

      repo.expects(:master_contains?).with(commit[:hash]).returns(true)
      repo.expects(:followees).with(commit[:hash]).returns([])

      post = first_post_of(Importer.new(repo).import_commit(commit))

      expect(post.cooked.scan("code").length).to eq(2)
      expect(post.excerpt).to eq("this is <a href=\"http://amaz.ing\">amazing</a>")
    end

    it "approves followed-up topics" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil)

      SiteSetting.code_review_enabled = true

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "a91843f0dc7b97e700dc85505404eafd62b7f8c5"
      }

      followee = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)

      commit[:hash] = "ca1208a63669d4d4ad7452367008d40fa090f645"
      follower = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).to include(SiteSetting.code_review_approved_tag)
    end

    it "approves followed-up topics with partial hashes" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil)

      SiteSetting.code_review_enabled = true

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "5ff6c10320cab7ef82ecda40c57cfb9e539b7e72"
      }

      followee = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)

      commit[:hash] = "dbfb2a1e11b6a4f33d35b26885193774e7ab9362"
      follower = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).to include(SiteSetting.code_review_approved_tag)
    end
  end
end
