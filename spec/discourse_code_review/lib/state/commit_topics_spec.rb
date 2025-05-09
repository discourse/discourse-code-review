# frozen_string_literal: true

require "rails_helper"

module DiscourseCodeReview
  describe State::CommitTopics do
    it "has robust sha detection" do
      text = (<<~STR).strip
        hello abcdf672, a723c123444!
        (abc2345662) {abcd87234} [#1209823bc]
        ,7862abcdf abcdefg722
        abc7827421119a
      STR

      shas = State::CommitTopics.detect_shas(text)

      expect(shas).to eq(
        %w[abcdf672 a723c123444 abc2345662 abcd87234 1209823bc 7862abcdf abc7827421119a],
      )
    end

    describe "#ensure_commit" do
      fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
      fab!(:category)

      it "can handle commits without message" do
        commit = {
          subject: "",
          body: "",
          email: "re@gis.com",
          github_login: "regis",
          github_id: "123",
          date: 10.day.ago,
          diff: "```\nwith a diff",
          hash: "1cd4e0bec9ebd50f353a52b9c197f713c0e1f422",
        }

        repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)

        topic_id =
          State::CommitTopics.ensure_commit(
            category_id: category.id,
            commit: commit,
            merged: false,
            repo_name: repo.name,
            user: user,
            followees: [],
          )

        expect(Topic.find_by(id: topic_id).title).to start_with("No message for commit ")
      end

      it "can handle deleted topics" do
        commit = {
          subject: "hello world",
          body: "this is the body\nwith an emoji :)",
          email: "sam@sam.com",
          github_login: "sam",
          github_id: "111",
          date: 1.day.ago,
          diff: "```\nwith a diff",
          hash: "154f503d2e99f904356b52f2fae9edcc495708fa",
        }

        repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)

        topic_id =
          State::CommitTopics.ensure_commit(
            category_id: category.id,
            commit: commit,
            merged: false,
            repo_name: repo.name,
            user: user,
            followees: [],
          )

        topic = Topic.find(topic_id)
        PostDestroyer.new(Discourse.system_user, topic.first_post).destroy
        expect(Topic.find_by(id: topic_id)).to eq(nil)

        topic_id =
          State::CommitTopics.ensure_commit(
            category_id: category.id,
            commit: commit,
            merged: false,
            repo_name: repo.name,
            user: user,
            followees: [],
          )

        expect(Topic.find_by(id: topic_id)).not_to eq(nil)
      end
    end
  end
end
