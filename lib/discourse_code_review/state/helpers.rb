# frozen_string_literal: true

module DiscourseCodeReview::State::Helpers
  class << self
    def ensure_topic_with_nonce(user:, nonce_name:, nonce_value:, custom_fields:, **kwargs)

      DistributedMutex.synchronize('code-review:ensure-topic-with-nonce') do
        ActiveRecord::Base.transaction(requires_new: true) do
          DiscourseCodeReview.without_rate_limiting do
            topic =
              find_topic_with_custom_field(
                name: nonce_name,
                value: nonce_value,
              )

            unless topic
              custom_fields.merge!({ nonce_name => nonce_value })

              post =
                PostCreator.create!(
                  user,
                  **kwargs,
                )

              topic = post.topic
              topic.custom_fields = custom_fields
              topic.save_custom_fields
              topic.update!(bumped_at: Time.zone.now)

              yield post if block_given?
            end

            topic
          end
        end
      end
    end

    def ensure_post_with_nonce(user:, topic_id:, nonce_name:, nonce_value:, custom_fields:, **kwargs)
      DistributedMutex.synchronize('code-review:ensure-post-with-nonce') do
        ActiveRecord::Base.transaction(requires_new: true) do
          DiscourseCodeReview.without_rate_limiting do
            post =
              find_post_with_custom_field(
                topic_id: topic_id,
                name: nonce_name,
                value: nonce_value,
              )

            unless post
              custom_fields.merge!({ nonce_name => nonce_value })

              post =
                PostCreator.create!(
                  user,
                  topic_id: topic_id,
                  **kwargs,
                )

              post.custom_fields = custom_fields
              post.save_custom_fields

              yield post if block_given?
            end

            post
          end
        end
      end
    end

    def ensure_closed_state_with_nonce(user:, closed:, topic:, nonce_name:, nonce_value:, created_at:)
      DistributedMutex.synchronize('code-review:ensure-post-with-nonce') do
        ActiveRecord::Base.transaction(requires_new: true) do
          post =
            find_post_with_custom_field(
              topic_id: topic.id,
              name: nonce_name,
              value: nonce_value,
            )

          unless post
            topic.update_status('closed', closed, user)

            last_post = last_post_for(topic.id)

            last_post.created_at = created_at
            last_post.skip_validation = true
            last_post.save!

            last_post.custom_fields[nonce_name] = nonce_value
            last_post.save_custom_fields
          end
        end
      end
    end

    def posts_with_custom_field(topic_id:, name:, value:)
      Post
        .where(
          topic_id: topic_id,
          id:
            PostCustomField
              .where(
                  name: name,
                  value: value,
              )
              .select(:post_id)
        )
    end

    def find_post_with_custom_field(topic_id:, name:, value:)
      posts_with_custom_field(
        topic_id: topic_id,
        name: name,
        value: value,
      ).first
    end

    def topics_with_custom_field(name:, value:)
      Topic
        .where(
          id:
            TopicCustomField
              .where(
                  name: name,
                  value: value,
              )
              .select(:topic_id)
        )
    end

    def find_topic_with_custom_field(name:, value:)
      topics_with_custom_field(name: name, value: value).first
    end

    def last_post_for(topic_id)
      Post
        .where(topic_id: topic_id)
        .order('post_number DESC')
        .limit(1)
        .first
    end
  end
end
