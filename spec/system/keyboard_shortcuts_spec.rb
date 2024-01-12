# frozen_string_literal: true

RSpec.describe "Keyboard shortcuts", type: :system do
  describe "<y>" do
    fab!(:post) { Fabricate(:post) }
    fab!(:current_user) { Fabricate(:admin) }

    let(:topic) { post.topic }
    let(:topic_page) { PageObjects::Pages::Topic.new }
    let(:tags) { topic.reload.tags.pluck(:name) }

    before do
      SiteSetting.code_review_enabled = true
      sign_in(current_user)
    end

    context "when on a commit topic" do
      fab!(:approved_tag) { Fabricate(:tag, name: "approved") }
      fab!(:pending_tag) { Fabricate(:tag, name: "pending") }

      context "when the commit is not approved" do
        before { topic.tags << pending_tag }

        it "approves the commit" do
          topic_page.visit_topic(topic)
          send_keys("y")
          expect(page).to have_current_path("/")
          expect(tags).to include("approved")
        end
      end

      context "when the commit is already approved" do
        before { topic.tags << approved_tag }

        it "does nothing" do
          topic_page.visit_topic(topic)
          expect { send_keys("y") }.not_to change { topic.reload.tags.pluck(:name) }
          expect(page).to have_current_path("/t/#{topic.slug}/#{topic.id}")
        end
      end
    end

    context "when on a normal topic page" do
      it "does nothing" do
        topic_page.visit_topic(topic)
        send_keys("y")
        expect(page).to have_current_path("/t/#{topic.slug}/#{topic.id}")
        expect(tags).not_to include("approved")
      end
    end
  end
end
