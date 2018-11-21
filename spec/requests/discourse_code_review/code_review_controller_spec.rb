require 'rails_helper'

describe DiscourseCodeReview::CodeReviewController do
  before do
    SiteSetting.code_review_enabled = true
  end
  context '.approve' do
    it 'does not allow you to approve your own commit' do
      user = Fabricate(:admin)
      commit = create_post(raw: "this is a fake commit", user: user)

      sign_in user

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(403)
    end
  end
end
