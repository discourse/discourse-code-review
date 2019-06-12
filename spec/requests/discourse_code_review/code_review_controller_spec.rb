# frozen_string_literal: true

require 'rails_helper'

describe DiscourseCodeReview::CodeReviewController do
  fab!(:signed_in_user) { Fabricate(:admin) }

  before do
    SiteSetting.code_review_enabled = true
    SiteSetting.tagging_enabled = true

    sign_in signed_in_user
  end

  context '.approve' do
    it 'doesn\'t allow you to approve your own commit if disabled' do

      SiteSetting.code_review_allow_self_approval = false

      commit = create_post(raw: "this is a fake commit", user: signed_in_user, tags: ["hi", SiteSetting.code_review_pending_tag])

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(403)
    end

    it 'skips commits from muted categories' do
      admin2 = Fabricate(:admin)

      muted_category = Fabricate(:category)

      CategoryUser.create!(
        user_id: signed_in_user.id,
        category_id: muted_category.id,
        notification_level: CategoryUser.notification_levels[:muted]
      )

      commit = create_post(
        raw: "this is a fake commit",
        tags: [SiteSetting.code_review_pending_tag],
        user: admin2
      )

      _muted_commit = create_post(
        raw: "this is a fake commit 2",
        tags: [SiteSetting.code_review_pending_tag],
        category: muted_category.id,
        user: admin2
      )

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(200)

      json = JSON.parse(response.body)
      expect(json["next_topic_url"]).to eq(nil)
    end

    it 'allows you to approve your own commit if enabled' do

      SiteSetting.code_review_allow_self_approval = true

      another_commit = create_post(
        raw: "this is an old commit",
        tags: [SiteSetting.code_review_pending_tag],
        user: Fabricate(:admin)
      )

      commit = create_post(raw: "this is a fake commit", user: signed_in_user, tags: ["hi", SiteSetting.code_review_pending_tag])

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(200)

      json = JSON.parse(response.body)
      expect(json["next_topic_url"]).to eq(another_commit.topic.relative_url)

      commit.topic.reload

      expect(commit.topic.tags.pluck(:name)).to include("hi", SiteSetting.code_review_approved_tag)
    end

    it 'does nothing when approving already approved posts' do
      commit = create_post(raw: "this is a fake commit", tags: ["hi", SiteSetting.code_review_pending_tag])

      expect { post '/code-review/approve.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(1)
      expect { post '/code-review/approve.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(0)
    end

    it 'notifies the topic author' do
      author = Fabricate(:user)
      commit =
        create_post(
          user: author,
          raw: "this is a fake commit",
          tags: ["hi", SiteSetting.code_review_pending_tag]
        )

      expect(commit.user.notifications.count).to eq(0)

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }

      expect(commit.user.notifications.count).to eq(1)
      notification = commit.user.notifications.first
      expect(JSON.parse(notification.data)).to eq({"num_approved_commits" => 1})
      expect(notification.topic_id).to eq(commit.topic.id)
      expect(notification.post_number).to eq(2)
    end

    it 'collapses commit approved notifications' do
      author = Fabricate(:user)

      commit1 =
        create_post(
          user: author,
          raw: "this is a fake commit",
          tags: ["hi", SiteSetting.code_review_pending_tag]
        )
      commit2 =
        create_post(
          user: author,
          raw: "this is another fake commit",
          tags: ["hi", SiteSetting.code_review_pending_tag]
        )

      expect(author.notifications.count).to eq(0)

      post '/code-review/approve.json', params: { topic_id: commit1.topic_id }
      post '/code-review/approve.json', params: { topic_id: commit2.topic_id }

      expect(author.notifications.count).to eq(1)
      notification = author.notifications.first
      expect(JSON.parse(notification.data)).to eq({"num_approved_commits" => 2})
      expect(notification.topic_id).to be_nil
      expect(notification.post_number).to be_nil
    end

    it 'doesn\'t disturb tracking users' do
      author = Fabricate(:user)
      commit =
        create_post(
          user: author,
          raw: "this is a fake commit",
          tags: ["hi", SiteSetting.code_review_pending_tag]
        )

      bystander = Fabricate(:user)

      PostTiming.record_new_timing(
        topic_id: commit.topic_id,
        msecs: 1000,
        user_id: bystander.id,
        post_number: 1,
      )

      TopicUser.change(
        bystander.id,
        commit.topic_id,
        notification_level: TopicUser.notification_levels[:tracking],
        last_read_post_number: 1,
        highest_seen_post_number: 1,
      )

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }

      topic_user =
        TopicUser.where(
          user_id: bystander.id,
          topic_id: commit.topic_id,
        ).first

      expect(topic_user.last_read_post_number).to eq(2)
      expect(topic_user.highest_seen_post_number).to eq(2)
    end
  end

  context '.followup' do
    it 'allows you to approve your own commit' do
      # If discourse-assign is present, we need to enable methods defined by the plugin.
      SiteSetting.assign_enabled = true if defined?(TopicAssigner)

      commit = create_post(raw: "this is a fake commit", user: signed_in_user, tags: ["hi", SiteSetting.code_review_approved_tag])

      post '/code-review/followup.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(200)

      commit.topic.reload

      expect(commit.topic.tags.pluck(:name)).to include("hi", SiteSetting.code_review_followup_tag)
    end

    it 'does nothing when following-up already followed-up posts' do
      commit = create_post(raw: "this is a fake commit", tags: ["hi", SiteSetting.code_review_pending_tag])

      expect { post '/code-review/followup.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(1)
      expect { post '/code-review/followup.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(0)
    end
  end

  context '.render_next_topic' do
    let(:other_user) { Fabricate(:admin) }

    it 'prefers unread topics over read ones' do
      commit = create_post(raw: "this is a fake commit", user: other_user, tags: ["hi", SiteSetting.code_review_pending_tag])
      read_commit = create_post(raw: "this is a read commit", user: other_user, tags: ["hi", SiteSetting.code_review_pending_tag], created_at: Time.zone.now + 1.hour)
      unread_commit = create_post(raw: "this is an unread commit", user: other_user, tags: ["hi", SiteSetting.code_review_pending_tag], created_at: Time.zone.now + 2.hours)
      TopicUser.create!(topic: read_commit.topic, user: signed_in_user, last_read_post_number: read_commit.topic.highest_post_number)

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }
      json = JSON.parse(response.body)
      expect(json["next_topic_url"]).to eq(unread_commit.topic.relative_url)
    end
  end

  it 'assigns and unassigns topic on followup and approve' do
    skip if !defined?(TopicAssigner)

    SiteSetting.assign_enabled = true
    SiteSetting.code_review_auto_assign_on_followup = true
    SiteSetting.code_review_auto_unassign_on_approve = true
    SiteSetting.code_review_allow_self_approval = true

    default_allowed_group = Group.find_by(name: 'staff')
    Fabricate(:group_user, user: user, group: default_allowed_group)

    commit = create_post(raw: "this is a fake commit", user: signed_in_user, tags: ["hi", SiteSetting.code_review_pending_tag])

    post '/code-review/followup.json', params: { topic_id: commit.topic_id }
    expect(response.status).to eq(200)
    expect(TopicQuery.new(signed_in_user, assigned: signed_in_user.username).list_latest.topics).to eq([commit.topic])

    post '/code-review/approve.json', params: { topic_id: commit.topic_id }
    expect(response.status).to eq(200)
    expect(TopicQuery.new(signed_in_user, assigned: signed_in_user.username).list_latest.topics).to eq([])
  end

end
