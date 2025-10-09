# frozen_string_literal: true

require "rails_helper"

module DiscourseCodeReview
  describe State::CommitApproval do
    fab!(:topic)
    fab!(:pr) do
      DiscourseCodeReview::PullRequest.new(owner: "owner", name: "name", issue_number: 101)
    end
    fab!(:approver, :user)
    fab!(:merged_by, :user)

    describe "#ensure_pr_merge_info_post" do
      it "does not consider duplicate approvers" do
        post =
          State::CommitApproval.approve(
            topic,
            [approver, merged_by] * 2,
            pr: pr,
            merged_by: merged_by,
          )
        expect(post.raw).to eq(
          "This commit appears in [#101](https://github.com/owner/name/pull/101) which was approved by #{approver.username} and #{merged_by.username}. It was merged by #{merged_by.username}.",
        )
      end
    end

    describe "creates notifications upon approval" do
      before { SiteSetting.code_review_enabled = true }

      it "doesn't consolidate notifications if they were created more than 6 hours ago" do
        second_topic = Fabricate(:topic, user: topic.user)
        second_pr =
          DiscourseCodeReview::PullRequest.new(owner: "owner", name: "name", issue_number: 102)

        State::CommitApproval.approve(topic, [approver, merged_by], pr: pr, merged_by: merged_by)
        first_notification =
          Notification.find_by(
            user: topic.user,
            notification_type: Notification.types[:code_review_commit_approved],
          )
        first_notification.update!(created_at: 7.hours.ago)

        State::CommitApproval.approve(
          second_topic,
          [approver, merged_by],
          pr: second_pr,
          merged_by: merged_by,
        )

        notifications =
          Notification.where(
            user: topic.user,
            notification_type: Notification.types[:code_review_commit_approved],
          )
        expect(notifications.count).to eq(2)
        expect(notifications.last.data_hash[:num_approved_commits]).to eq(1)
      end
    end
  end
end
