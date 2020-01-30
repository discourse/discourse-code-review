# frozen_string_literal: true

require "rails_helper"

describe ListController do
  before do
    user = Fabricate(:user, username: 't.testeur')
    sign_in(user)
  end

  context "approval-given route" do
    it "handles periods in usernames" do
      get "/topics/approval-given/t.testeur.json"
      expect(response.status).to eq(204) # No content
    end
  end

  context "approval-pending route" do
    it "handles periods in usernames" do
      get "/topics/approval-pending/t.testeur.json"
      expect(response.status).to eq(204) # No content
    end
  end
end
