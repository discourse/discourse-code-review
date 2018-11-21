class ::DiscourseCodeReview::CodeReviewController < ::ApplicationController
  before_action :ensure_logged_in
  before_action :ensure_staff

  def followup
    topic = Topic.find_by(id: params[:topic_id])

    PostRevisor.new(topic.ordered_posts.first, topic)
      .revise!(current_user,
        category_id: SiteSetting.code_review_followup_category_id)

    topic.add_moderator_post(
      current_user,
      nil,
      bump: false,
      post_type: Post.types[:small_action],
      action_code: "followup"
    )

    render_next_topic

  end

  def approve
    topic = Topic.find_by(id: params[:topic_id])

    PostRevisor.new(topic.ordered_posts.first, topic)
      .revise!(current_user,
        category_id: SiteSetting.code_review_approved_category_id)

    topic.add_moderator_post(
      current_user,
      nil,
      bump: false,
      post_type: Post.types[:small_action],
      action_code: "approved"
    )

    render_next_topic

  end

  protected

  def render_next_topic
    next_topic = Topic
      .where(category_id: SiteSetting.code_review_pending_category_id)
      .where('topics.id not in (select categories.topic_id from categories where categories.id = category_id)')
      .where('user_id <> ?', current_user.id)
      .order('bumped_at asc')
      .first

    url = next_topic&.relative_url

    render json: {
      next_topic_url: url
    }
  end

end
