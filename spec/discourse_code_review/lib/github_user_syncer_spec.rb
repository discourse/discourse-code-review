# frozen_string_literal: true

describe DiscourseCodeReview::GithubUserSyncer do
  describe "#ensure_user" do
    context "when enable_staged_users is enabled" do
      before { SiteSetting.enable_staged_users = true }

      it "uses name for username by default" do
        name = "Bill"
        email = "billgates@gmail.com"

        user_syncer = DiscourseCodeReview::GithubUserSyncer.new(nil)
        user_syncer.ensure_user(name: name, email: email)

        staged_user = User.find_by_email(email)
        expect(staged_user.username).to eq(name)
        expect(staged_user).to be_staged
      end

      it "doesn't use email for username suggestions by default" do
        email = "billgates@gmail.com"

        user_syncer = DiscourseCodeReview::GithubUserSyncer.new(nil)
        user_syncer.ensure_user(name: nil, email: email)

        staged_user = User.find_by_email(email)
        expect(staged_user.username).to eq("user1") # not "billgates" extracted from billgates@gmail.com
      end

      it "uses email for username if enabled and name consists entirely of disallowed characters" do
        SiteSetting.use_email_for_username_and_name_suggestions = true
        SiteSetting.unicode_usernames = false
        name = "άκυρος"
        email = "billgates@gmail.com"

        user_syncer = DiscourseCodeReview::GithubUserSyncer.new(nil)
        user_syncer.ensure_user(name: name, email: email)

        staged_user = User.find_by_email(email)
        expect(staged_user.username).to eq("billgates")
      end
    end

    context "when enable_staged_users is disabled" do
      before { SiteSetting.enable_staged_users = false }

      it "uses system user" do
        name = "Bill"
        email = "billgates@gmail.com"

        user_syncer = DiscourseCodeReview::GithubUserSyncer.new(nil)
        expect {
          user = user_syncer.ensure_user(name: name, email: email)
          expect(user).to eq(Discourse.system_user)
        }.to_not change { User.count }
      end
    end
  end
end
