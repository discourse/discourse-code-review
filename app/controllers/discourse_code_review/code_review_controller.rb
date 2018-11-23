class ::DiscourseCodeReview::CodeReviewController < ::ApplicationController
  before_action :ensure_logged_in
  before_action :ensure_staff

  def followup
    topic = Topic.find_by(id: params[:topic_id])

    tags = topic.tags.pluck(:name)

    tags -= [
      SiteSetting.code_review_approved_tag,
      SiteSetting.code_review_pending_tag
    ]

    tags << SiteSetting.code_review_followup_tag

    DiscourseTagging.tag_topic_by_names(topic, Guardian.new(current_user), tags)

    topic.add_moderator_post(
      current_user,
      nil,
      bump: false,
      post_type: Post.types[:small_action],
      action_code: "followup"
    )

    render_next_topic(topic.category_id)

  end

  def approve

    topic = Topic.find_by(id: params[:topic_id])

    tags = topic.tags.pluck(:name)

    tags -= [
      SiteSetting.code_review_followup_tag,
      SiteSetting.code_review_pending_tag
    ]

    tags << SiteSetting.code_review_approved_tag

    DiscourseTagging.tag_topic_by_names(topic, Guardian.new(current_user), tags)

    topic.add_moderator_post(
      current_user,
      nil,
      bump: false,
      post_type: Post.types[:small_action],
      action_code: "approved"
    )

    render_next_topic(topic.category_id)

  end

  protected

  def render_next_topic(category_id)
    next_topic = Topic
      .joins(:tags)
      .where('tags.name = ?', SiteSetting.code_review_pending_tag)
      .where(category_id: category_id)
      .where('user_id <> ?', current_user.id)
      .order('bumped_at asc')
      .first

    url = next_topic&.relative_url

    render json: {
      next_topic_url: url
    }
  end

end
