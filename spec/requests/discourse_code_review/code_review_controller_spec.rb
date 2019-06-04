# frozen_string_literal: true

require 'rails_helper'

describe DiscourseCodeReview::CodeReviewController do

  before do
    SiteSetting.code_review_enabled = true
    SiteSetting.tagging_enabled = true
  end

  context '.approve' do
    it 'allows you to approve your own commit if enabled' do

      SiteSetting.code_review_allow_self_approval = false

      user = Fabricate(:admin)
      commit = create_post(raw: "this is a fake commit", user: user, tags: ["hi", SiteSetting.code_review_pending_tag])

      sign_in user

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(403)
    end

    it 'skips commits from muted categories' do
      admin = Fabricate(:admin)
      admin2 = Fabricate(:admin)

      muted_category = Fabricate(:category)

      CategoryUser.create!(
        user_id: admin.id,
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

      sign_in admin

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

      user = Fabricate(:admin)
      commit = create_post(raw: "this is a fake commit", user: user, tags: ["hi", SiteSetting.code_review_pending_tag])

      sign_in user

      post '/code-review/approve.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(200)

      json = JSON.parse(response.body)
      expect(json["next_topic_url"]).to eq(another_commit.topic.relative_url)

      commit.topic.reload

      expect(commit.topic.tags.pluck(:name)).to include("hi", SiteSetting.code_review_approved_tag)
    end

    it 'does nothing when approving already approved posts' do
      sign_in Fabricate(:admin)
      commit = create_post(raw: "this is a fake commit", tags: ["hi", SiteSetting.code_review_pending_tag])

      expect { post '/code-review/approve.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(1)
      expect { post '/code-review/approve.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(0)
    end
  end

  context '.followup' do
    it 'allows you to approve your own commit' do
      # If discourse-assign is present, we need to enable methods defined by the plugin.
      SiteSetting.assign_enabled = true if defined?(TopicAssigner)

      user = Fabricate(:admin)
      commit = create_post(raw: "this is a fake commit", user: user, tags: ["hi", SiteSetting.code_review_approved_tag])

      sign_in user

      post '/code-review/followup.json', params: { topic_id: commit.topic_id }
      expect(response.status).to eq(200)

      commit.topic.reload

      expect(commit.topic.tags.pluck(:name)).to include("hi", SiteSetting.code_review_followup_tag)
    end

    it 'does nothing when following-up already followed-up posts' do
      sign_in Fabricate(:admin)
      commit = create_post(raw: "this is a fake commit", tags: ["hi", SiteSetting.code_review_pending_tag])

      expect { post '/code-review/followup.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(1)
      expect { post '/code-review/followup.json', params: { topic_id: commit.topic_id } }.to change { commit.topic.posts.count }.by(0)
    end
  end

  context '.render_next_topic' do

    let(:user) { Fabricate(:admin) }
    let(:other_user) { Fabricate(:admin) }

    it 'prefers unread topics over read ones' do
      commit = create_post(raw: "this is a fake commit", user: other_user, tags: ["hi", SiteSetting.code_review_pending_tag])
      read_commit = create_post(raw: "this is a read commit", user: other_user, tags: ["hi", SiteSetting.code_review_pending_tag], created_at: Time.zone.now + 1.hour)
      unread_commit = create_post(raw: "this is an unread commit", user: other_user, tags: ["hi", SiteSetting.code_review_pending_tag], created_at: Time.zone.now + 2.hours)
      TopicUser.create!(topic: read_commit.topic, user: user, last_read_post_number: read_commit.topic.highest_post_number)

      sign_in user

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
    user = Fabricate(:admin, groups: [default_allowed_group])
    commit = create_post(raw: "this is a fake commit", user: user, tags: ["hi", SiteSetting.code_review_pending_tag])

    sign_in user

    post '/code-review/followup.json', params: { topic_id: commit.topic_id }
    expect(response.status).to eq(200)
    expect(TopicQuery.new(user, assigned: user.username).list_latest.topics).to eq([commit.topic])

    post '/code-review/approve.json', params: { topic_id: commit.topic_id }
    expect(response.status).to eq(200)
    expect(TopicQuery.new(user, assigned: user.username).list_latest.topics).to eq([])
  end

end
