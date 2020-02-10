# frozen_string_literal: true

module DiscourseCodeReview
  module CommitApprovalStateService
    def self.approve(topic, approver)
      tags = topic.tags.pluck(:name)

      if !tags.include?(SiteSetting.code_review_approved_tag)
        tags -= [
          SiteSetting.code_review_followup_tag,
          SiteSetting.code_review_pending_tag
        ]

        tags << SiteSetting.code_review_approved_tag

        DiscourseTagging.tag_topic_by_names(topic, Guardian.new(approver), tags)

        old_highest_post_number = topic.highest_post_number
        post =
          topic.add_moderator_post(
            approver,
            nil,
            bump: false,
            post_type: Post.types[:small_action],
            action_code: "approved"
          )

        PostTiming.pretend_read(
          topic.id,
          old_highest_post_number,
          post.post_number
        )

        Notification.transaction do
          destroyed_notifications =
            topic.user.notifications
              .where(
                notification_type: Notification.types[:code_review_commit_approved],
              )
              .where('created_at > ?', 6.hours.ago)
              .destroy_all

          previous_approved =
            destroyed_notifications.inject(0) do |sum, notification|
              sum + JSON.parse(notification.data)['num_approved_commits'].to_i
            end

          if previous_approved == 0
            topic.user.notifications.create(
              notification_type: Notification.types[:code_review_commit_approved],
              topic_id: topic.id,
              post_number: post.post_number,
              data: { num_approved_commits: 1 }.to_json
            )
          else
            topic.user.notifications.create(
              notification_type: Notification.types[:code_review_commit_approved],
              data: { num_approved_commits: previous_approved + 1 }.to_json
            )
          end
        end

        if SiteSetting.code_review_auto_unassign_on_approve && topic.user.staff?
          DiscourseEvent.trigger(:unassign_topic, topic, approver)
        end
      end
    end

    def self.followup(topic, actor)
      tags = topic.tags.pluck(:name)

      if !tags.include?(SiteSetting.code_review_followup_tag)
        tags -= [
          SiteSetting.code_review_approved_tag,
          SiteSetting.code_review_pending_tag
        ]

        tags << SiteSetting.code_review_followup_tag

        DiscourseTagging.tag_topic_by_names(topic, Guardian.new(actor), tags)

        topic.add_moderator_post(
          actor,
          nil,
          bump: false,
          post_type: Post.types[:small_action],
          action_code: "followup"
        )

        if SiteSetting.code_review_auto_assign_on_followup && topic.user.staff?
          DiscourseEvent.trigger(:assign_topic, topic, topic.user, actor)
        end
      end
    end
  end
end
