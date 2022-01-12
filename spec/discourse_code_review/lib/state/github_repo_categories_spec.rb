# frozen_string_literal: true

require "rails_helper"

describe DiscourseCodeReview::State::GithubRepoCategories do
  it "can create a new category" do
    expect {
      c = described_class.ensure_category(repo_name: "repo-name", repo_id: 242)
      expect(c.name).to eq("repo-name")
      expect(c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_ID]).to eq("242")
      expect(c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME]).to eq("repo-name")
    }.to change { Category.count }.by(1)
  end

  it "can use an existing category" do
    c = Fabricate(:category, name: "repo-name")
    DiscourseCodeReview::GithubRepoCategory.create!(category_id: c.id, name: 'repo-name')
    c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME] = "repo-name"
    c.save_custom_fields
    expect {
      c = described_class.ensure_category(repo_name: "repo-name", repo_id: 242)
      expect(c.name).to eq("repo-name")
    }.to_not change { Category.count }
    # updates repository ID in custom field
    expect(c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_ID]).to eq("242")
  end

  it "can use an existing category based on repository ID" do
    c = Fabricate(:category, name: "repo-name")
    DiscourseCodeReview::GithubRepoCategory.create!(category_id: c.id, name: 'repo-name', repo_id: '242')
    c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_ID] = "242"
    c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME] = "repo-name"
    c.save_custom_fields
    expect {
      c = described_class.ensure_category(repo_name: "new-repo-name", repo_id: "242")
      expect(c.name).to eq("repo-name")
    }.to_not change { Category.count }
    # updates repository name in custom field
    expect(c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME]).to eq("new-repo-name")
  end

  it "does not break when repository ID is not present" do
    c = Fabricate(:category, name: "repo-name")
    c.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME] = "repo-name"
    DiscourseCodeReview::GithubRepoCategory.create!(category_id: c.id, name: 'repo-name')
    c.save_custom_fields
    expect {
      c = described_class.ensure_category(repo_name: "repo-name")
      expect(c.name).to eq("repo-name")
    }.to_not change { Category.count }
  end

  it "does not create a new category without repo_id" do
    expect {
      described_class.ensure_category(repo_name: "repo-name")
    }.to_not change { Category.count }
  end

  context "code_review_default_mute_new_categories enabled" do
    before do
      SiteSetting.code_review_default_mute_new_categories = true
    end

    it "can add the category" do
      c = described_class.ensure_category(repo_name: "repo-name", repo_id: 24)
      expect(SiteSetting.default_categories_muted).to eq(c.id.to_s)

      c2 = described_class.ensure_category(repo_name: "repo-name2", repo_id: 25)
      expect(SiteSetting.default_categories_muted.split("|").map(&:to_i)).to contain_exactly(c.id, c2.id)
    end

    it "removes categories that were deleted" do
      c = described_class.ensure_category(repo_name: "repo-name", repo_id: 24)
      expect(SiteSetting.default_categories_muted).to eq(c.id.to_s)

      c.destroy

      c2 = described_class.ensure_category(repo_name: "repo-name2", repo_id: 25)
      expect(SiteSetting.default_categories_muted.split("|").map(&:to_i)).to contain_exactly(c2.id)
    end
  end
end
