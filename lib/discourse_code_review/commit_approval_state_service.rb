# frozen_string_literal: true

module DiscourseCodeReview::CommitApprovalStateService
  PR_MERGE_INFO_PR = "pr merge info pr"
  PR_MERGE_INFO_DATA = "pr merge info data"

  class << self
    def approve(topic, approvers, pr: nil, merged_by: nil)
      last_post = nil
      approvers.each do |approver|
        last_post = ensure_approved_post(topic, approver)
      end

      unless approvers.empty?
        transition_to_approved(topic) do
          send_approved_notification(topic, last_post)

          if SiteSetting.code_review_auto_unassign_on_approve && topic.user.staff?
            DiscourseEvent.trigger(:unassign_topic, topic, approvers.first)
          end
        end
      end

      if pr
        ensure_pr_merge_info_post(topic, pr, approvers, merged_by)
      end
    end

    def followup(topic, actor)
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

    private

    def ensure_approved_post(topic, approver)
      post =
        Post.where(
          topic_id: topic.id,
          user_id: approver.id,
          action_code: "approved"
        ).first

      unless post
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
      end

      post
    end

    def transition_to_approved(topic)
      tags = topic.tags.pluck(:name)
      if !tags.include?(SiteSetting.code_review_approved_tag)
        tags -= [
          SiteSetting.code_review_followup_tag,
          SiteSetting.code_review_pending_tag
        ]

        tags << SiteSetting.code_review_approved_tag

        DiscourseTagging.tag_topic_by_names(topic, Guardian.new(Discourse.system_user), tags)

        yield
      end
    end

    def send_approved_notification(topic, post)
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
    end

    def ensure_pr_merge_info_post(topic, pr, approvers, merged_by)
      old_highest_post_number = topic.highest_post_number
      pr_string = "#{pr.owner}/#{pr.name}##{pr.issue_number}"

      post =
        Post
          .where(
            topic_id: topic.id,
            id:
              PostCustomField
                .where(
                    name: PR_MERGE_INFO_PR,
                    value: pr_string
                )
                .select(:post_id)
          )
          .first

      unless post
        custom_fields = {
          PR_MERGE_INFO_PR => pr_string,
          PR_MERGE_INFO_DATA => {
            'merged_by': merged_by.id,
            'approvers': approvers.map(&:id),
          }.to_json
        }

        pr_url = "https://github.com/#{pr.owner}/#{pr.name}/pull/#{pr.issue_number}"
        raw_parts = ["This commit appears in [##{pr.issue_number}](#{pr_url}) which was"]

        unless approvers.empty?
          approvers_string =
            approvers
              .map(&:username)
              .to_sentence

          raw_parts << "approved by #{approvers_string}. It was"
        end

        raw_parts << "merged by #{merged_by.username}."

        post =
          PostCreator.create!(
            Discourse.system_user,
            topic_id: topic.id,
            bump: false,
            post_type: Post.types[:small_action],
            action_code: "pr_merge_info",
            raw: raw_parts.join(" "),
            custom_fields: custom_fields
          )

        PostTiming.pretend_read(
          topic.id,
          old_highest_post_number,
          post.post_number
        )
      end

      post
    end
  end
end
