# frozen_string_literal: true

module DiscourseCodeReview::State::CommitApproval
  PR_MERGE_INFO_PR = "pr merge info pr"
  PR_MERGE_INFO_DATA = "pr merge info data"

  class << self
    def skip(topic, user)
      if SiteSetting.code_review_skip_duration_minutes > 0
        DiscourseCodeReview::SkippedCodeReview.upsert({
            topic_id: topic.id,
            user_id: user.id,
            expires_at: SiteSetting.code_review_skip_duration_minutes.minutes.from_now,
            created_at: Time.zone.now,
            updated_at: Time.zone.now,
          },
          unique_by: [:topic_id, :user_id]
        )
      end
    end

    def approve(topic, approvers, pr: nil, merged_by: nil)
      last_post = nil
      approvers.each do |approver|
        last_post = ensure_approved_post(topic, approver)
      end

      unless approvers.empty?
        transition_to_approved(topic) do
          send_approved_notification(topic, last_post)

          if SiteSetting.code_review_auto_unassign_on_approve && topic.user.can_review_code?
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

        if SiteSetting.code_review_auto_assign_on_followup && topic.user.can_review_code?
          DiscourseEvent.trigger(:assign_topic, topic, topic.user, actor)
        end
      end
    end

    def followed_up(followee_topic, follower_topic)
      last_post =
        followee_topic.add_moderator_post(
          follower_topic.user,
          " [#{follower_topic.title}](#{follower_topic.url})",
          bump: false,
          post_type: Post.types[:small_action],
          action_code: "followed_up"
        )

      transition_to_approved(followee_topic) do
        send_approved_notification(followee_topic, last_post)

        if SiteSetting.code_review_auto_unassign_on_approve && followee_topic.user.can_review_code?
          DiscourseEvent.trigger(
            :unassign_topic,
            followee_topic,
            followee_topic.user,
            follower_topic.user,
          )
        end
      end
    end

    private

    def ensure_approved_post(topic, approver)
      DistributedMutex.synchronize("code-review:ensure-approved-post:#{topic.id}") do
        ActiveRecord::Base.transaction(requires_new: true) do
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
      end
    end

    def transition_to_approved(topic)
      already_approved = true

      DistributedMutex.synchronize("code-review:ensure-approved-tag:#{topic.id}") do
        tags = topic.tags.pluck(:name)
        if !tags.include?(SiteSetting.code_review_approved_tag)
          tags -= [
            SiteSetting.code_review_followup_tag,
            SiteSetting.code_review_pending_tag
          ]

          tags << SiteSetting.code_review_approved_tag

          DiscourseTagging.tag_topic_by_names(topic, Guardian.new(Discourse.system_user), tags)
          already_approved = false
        end
      end

      yield unless already_approved
    end

    def send_approved_notification(topic, post)
      if !topic.user
        return
      end

      notify = topic.user.custom_fields[DiscourseCodeReview::NOTIFY_REVIEW_CUSTOM_FIELD]

      # can be nil as well
      if notify == false
        return
      end

      Notification.consolidate_or_create!(
        notification_type: Notification.types[:code_review_commit_approved],
        topic_id: topic.id,
        user: topic.user,
        post_number: post.post_number,
        data: { num_approved_commits: 1 }.to_json
      )
    end

    def ensure_pr_merge_info_post(topic, pr, approvers, merged_by)
      pr_string = "#{pr.owner}/#{pr.name}##{pr.issue_number}"

      pr_url = "https://github.com/#{pr.owner}/#{pr.name}/pull/#{pr.issue_number}"
      raw_parts = ["This commit appears in [##{pr.issue_number}](#{pr_url}) which was"]

      unless approvers.empty?
        approvers_string =
          approvers
            .map(&:username)
            .uniq
            .to_sentence

        raw_parts << "approved by #{approvers_string}. It was"
      end

      raw_parts << "merged by #{merged_by.username}."

      custom_fields = {
        PR_MERGE_INFO_DATA => {
          'merged_by': merged_by.id,
          'approvers': approvers.map(&:id),
        }.to_json
      }

      # TODO:
      #   There's a race condition here, since the highest_post_number could
      #   change before we use it.
      old_highest_post_number = topic.highest_post_number

      DiscourseCodeReview::State::Helpers
        .ensure_post_with_nonce(
          action_code: "pr_merge_info",
          bump: false,
          custom_fields: custom_fields,
          nonce_name: PR_MERGE_INFO_PR,
          nonce_value: pr_string,
          post_type: Post.types[:small_action],
          raw: raw_parts.join(" "),
          topic_id: topic.id,
          user: Discourse.system_user,
        ) do |post|
          PostTiming.pretend_read(
            topic.id,
            old_highest_post_number,
            post.post_number
          )
        end
    end

  end
end
