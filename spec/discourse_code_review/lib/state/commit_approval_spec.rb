# frozen_string_literal: true

require 'rails_helper'

module DiscourseCodeReview
  describe State::CommitApproval do
    fab!(:topic) { Fabricate(:topic) }
    fab!(:pr) {
      DiscourseCodeReview::PullRequest.new(
        owner: "owner",
        name: "name",
        issue_number: 101,
      )
    }
    fab!(:approver) { Fabricate(:user) }
    fab!(:merged_by) { Fabricate(:user) }

    describe "#ensure_pr_merge_info_post" do
      it "does not consider duplicate approvers" do
        post = State::CommitApproval.approve(topic, [approver, merged_by] * 2, pr: pr, merged_by: merged_by)
        expect(post.raw).to eq("This commit appears in [#101](https://github.com/owner/name/pull/101) which was approved by #{approver.username} and #{merged_by.username}. It was merged by #{merged_by.username}.")
      end
    end
  end
end
