# frozen_string_literal: true

describe ListController do
  fab!(:user) { Fabricate(:user, username: "t.testeur") }
  fab!(:topic) { Fabricate(:topic, user: user) }
  fab!(:pr) do
    DiscourseCodeReview::PullRequest.new(owner: "owner", name: "name", issue_number: 101)
  end
  fab!(:approver) { Fabricate(:user, username: "approver-user") }
  fab!(:merged_by, :user)
  fab!(:pending_tag) { Fabricate(:tag, name: "pending") }
  fab!(:pending_topic) { Fabricate(:topic, user: user, tags: [pending_tag]) }

  before do
    SiteSetting.code_review_enabled = true
    sign_in(approver)

    DiscourseCodeReview::State::CommitApproval.approve(
      topic,
      [approver, merged_by] * 2,
      pr: pr,
      merged_by: merged_by,
    )
  end

  context "for approval-given route" do
    it "handles periods in usernames and lists topics authored by this username" do
      get "/topics/approval-given/t.testeur.json"
      topic_list = response.parsed_body["topic_list"]
      expect(topic_list["topics"].size).to eq(1)
      expect(topic_list["topics"][0]["id"]).to eq(topic.id)
    end

    it "lists only topics authored by the given username" do
      get "/topics/approval-given/approver-user.json"
      topic_list = response.parsed_body["topic_list"]
      expect(topic_list["topics"].size).to eq(0)
    end

    it "returns a 404 for non-existing users" do
      get "/topics/approval-given/non-existing-user.json"
      expect(response.status).to eq(404)
      expect(response.parsed_body["errors"]).to eq(
        [I18n.t("approval_list.user_not_found", { username: "non-existing-user" })],
      )
    end
  end

  context "for approval-pending route" do
    it "handles periods in usernames and lists topics authored by this username" do
      get "/topics/approval-pending/t.testeur.json"
      topic_list = response.parsed_body["topic_list"]
      expect(topic_list["topics"].size).to eq(1)
      expect(topic_list["topics"][0]["id"]).to eq(pending_topic.id)
    end

    it "lists only topics authored by the given username" do
      get "/topics/approval-pending/approver-user.json"
      topic_list = response.parsed_body["topic_list"]
      expect(topic_list["topics"].size).to eq(0)
    end

    it "returns a 404 for non-existing users" do
      get "/topics/approval-pending/non-existing-user.json"
      expect(response.status).to eq(404)
      expect(response.parsed_body["errors"]).to eq(
        [I18n.t("approval_list.user_not_found", { username: "non-existing-user" })],
      )
    end
  end
end
