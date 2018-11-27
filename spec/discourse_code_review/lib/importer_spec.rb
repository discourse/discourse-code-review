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
  end
end
