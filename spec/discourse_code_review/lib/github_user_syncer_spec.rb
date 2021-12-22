# frozen_string_literal: true

require 'rails_helper'

describe DiscourseCodeReview::GithubUserSyncer do
  context "#ensure_user" do
    it "uses name for username by default" do
      name = "Bill"
      email = "billgates@gmail.com"

      user_syncer = DiscourseCodeReview::GithubUserSyncer.new(nil)
      user_syncer.ensure_user(name: name, email: email)

      staged_user = User.find_by_email(email)
      expect(staged_user.username).to eq(name)
    end

    it "uses email for username if name consists entirely of disallowed characters" do
      SiteSetting.unicode_usernames = false
      name = "άκυρος"
      email = "billgates@gmail.com"

      user_syncer = DiscourseCodeReview::GithubUserSyncer.new(nil)
      user_syncer.ensure_user(name: name, email: email)

      staged_user = User.find_by_email(email)
      expect(staged_user.username).to eq("billgates")
    end
  end
end
