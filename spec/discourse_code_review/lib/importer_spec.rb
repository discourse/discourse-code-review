# frozen_string_literal: true

require 'rails_helper'

module DiscourseCodeReview
  describe Importer do

    it "has robust sha detection" do
      text = (<<~STR).strip
        hello abcdf672, a723c123444!
        (abc2345662) {abcd87234} [#1209823bc]
        ,7862abcdf abcdefg722
        abc7827421119a
      STR

      shas = Importer.new(nil).detect_shas(text)

      expect(shas).to eq(%w{
       abcdf672
       a723c123444
       abc2345662
       abcd87234
       1209823bc
       7862abcdf
       abc7827421119a
      })
    end

    it "can look up a category id consistently" do

      # lets muck stuff up first ... and create a dupe category
      Category.create!(name: 'discourse', user: Discourse.system_user)

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new)
      id = Importer.new(repo).category_id

      expect(id).to be > 0
      expect(Importer.new(repo).category_id).to eq(id)
    end

    it "can cleanly associate old commits" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new)

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

      post = Importer.new(repo).import_commit(commit)

      commit[:hash] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      commit[:body] = "ab2787347ff (this is\nfollowing up on a1db15fe)"
      post2 = Importer.new(repo).import_commit(commit)

      expect(post2.cooked).to include(post.topic.url)

      # expect a backlink
      expect(post.topic.posts.length).to eq(2)

    end

    it "can handle complex imports" do

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new)

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

      post = Importer.new(repo).import_commit(commit)

      expect(post.cooked.scan("code").length).to eq(2)
      expect(post.excerpt).to eq("this is <a href=\"http://amaz.ing\">amazing</a>")
    end

    it "#auto_link_commits" do
      topic = Fabricate(:topic)
      topic.custom_fields[DiscourseCodeReview::CommitHash] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      topic.save
      topic2 = Fabricate(:topic)
      topic2.custom_fields[DiscourseCodeReview::CommitHash] = "a1db15feadc7951d8a2b4ae63384babd6c568ae0"
      topic2.save

      result = Importer.new(nil).auto_link_commits("a1db15feadc and another one dbbadb5c357")
      markdown = "[a1db15feadc](#{topic2.url}) and another one [dbbadb5c357](#{topic.url})"
      cooked = PrettyText.cook(markdown)
      expect(result[0]).to eq(markdown)
      expect(result[2].to_html).to eq(cooked)
    end
  end
end
