require 'rails_helper'

module DiscourseCodeReview
  describe Importer do
    it "can look up a category id consistently" do

      # lets muck stuff up first ... and create a dupe category
      Category.create!(name: 'discourse', user: Discourse.system_user)

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new)
      id = Importer.new(repo).category_id

      expect(id).to be > 0
      expect(Importer.new(repo).category_id).to eq(id)
    end

    it "can escape diff ```" do

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new)

      diff = "```\nwith a diff"

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: diff
      }

      post = Importer.new(repo).import_commit(commit)

      expect(post.cooked.scan("code").length).to eq(2)
    end
  end
end
