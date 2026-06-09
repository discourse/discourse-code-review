# frozen_string_literal: true

module DiscourseCodeReview
  describe State::CommitApproval do
    fab!(:pending_tag) { Fabricate(:tag, name: SiteSetting.code_review_pending_tag) }
    fab!(:topic) { Fabricate(:topic, tags: [pending_tag]) }
    fab!(:pr) do
      DiscourseCodeReview::PullRequest.new(owner: "owner", name: "name", issue_number: 101)
    end
    fab!(:approver, :admin)
    fab!(:merged_by, :admin)

    before do
      DiscourseCodeReview::CommitTopic.create!(topic_id: topic.id, sha: SecureRandom.hex(20))
    end

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

    describe ".followup" do
      fab!(:reviewer_group, :group)
      fab!(:actor, :user)
      fab!(:private_group, :group)

      fab!(:private_category) { Fabricate(:private_category, group: private_group) }

      fab!(:private_topic) do
        Fabricate(:topic, category: private_category, tags: [pending_tag], user: Fabricate(:admin))
      end

      before do
        SiteSetting.code_review_allowed_groups = reviewer_group.id.to_s
        SiteSetting.tagging_enabled = true
        reviewer_group.add(actor)
        DiscourseCodeReview::CommitTopic.create!(
          topic_id: private_topic.id,
          sha: SecureRandom.hex(20),
        )
      end

      it "requires the actor to see the topic" do
        expect(actor.guardian.can_see?(private_topic)).to eq(false)

        expect { State::CommitApproval.followup(private_topic, actor) }.to raise_error(
          Discourse::InvalidAccess,
        )
        expect(private_topic.reload.tags.pluck(:name)).to contain_exactly(
          SiteSetting.code_review_pending_tag,
        )
      end
    end

    describe "creates notifications upon approval" do
      before { SiteSetting.code_review_enabled = true }

      it "doesn't consolidate notifications if they were created more than 6 hours ago" do
        second_topic = Fabricate(:topic, tags: [pending_tag], user: topic.user)
        DiscourseCodeReview::CommitTopic.create!(
          topic_id: second_topic.id,
          sha: SecureRandom.hex(20),
        )
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
