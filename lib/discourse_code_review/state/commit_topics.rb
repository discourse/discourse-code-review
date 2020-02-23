# frozen_string_literal: true

module DiscourseCodeReview::State::CommitTopics
  class << self
    def auto_link_commits(text, doc = nil)
      linked_commits = find_linked_commits(text)
      if (linked_commits.length > 0)
        doc ||= Nokogiri::HTML::fragment(PrettyText.cook(text))
        skip_tags = ["a", "code"]
        linked_commits.each do |hash, topic|
          doc.traverse do |node|
            if node.text? && !skip_tags.include?(node.parent&.name)
              node.replace node.content.gsub(hash, "<a href='#{topic.url}'>#{hash}</a>")
            end
          end
          text = HtmlToMarkdown.new(doc.to_html).to_markdown
        end
      end
      [text, linked_commits, doc]
    end

    def detect_shas(text)
      text.scan(/(?:[^a-zA-Z0-9]|^)([a-f0-9]{8,})(?:[^a-zA-Z0-9]|$)/).flatten
    end

    def ensure_commit_comment(topic_id, comment)
      DistributedMutex.synchronize('code-review:create-commit-comment-post') do
        ActiveRecord::Base.transaction(requires_new: true) do
          # skip if we already have the comment
          unless PostCustomField.exists?(name: DiscourseCodeReview::GITHUB_ID, value: comment[:id])
            login = comment[:login] || "unknown"
            user = DiscourseCodeReview.github_user_syncer.ensure_user(name: login, github_login: login)

            context = ""
            if comment[:line_content]
              context = <<~MD
                [quote]
                #{comment[:path]}

                ```diff
                #{comment[:line_content]}
                ```

                [/quote]

              MD
            end

            custom_fields = { DiscourseCodeReview::GITHUB_ID => comment[:id] }
            custom_fields[DiscourseCodeReview::COMMENT_PATH] = comment[:path] if comment[:path].present?
            custom_fields[DiscourseCodeReview::COMMENT_POSITION] = comment[:position] if comment[:position].present?

            PostCreator.create!(
              user,
              raw: context + comment[:body],
              skip_validations: true,
              created_at: comment[:created_at],
              topic_id: topic_id,
              custom_fields: custom_fields
            )
          end
        end
      end
    end

    def ensure_commit(commit:, merged:, repo_name:, user:, category_id:)
      DistributedMutex.synchronize('code-review:create-commit-topic') do
        ActiveRecord::Base.transaction(requires_new: true) do
          link = <<~LINK
            [<small>GitHub</small>](https://github.com/#{repo_name}/commit/#{commit[:hash]})
          LINK

          title = commit[:subject]
          # we add a unicode zero width joiner so code block is not corrupted
          diff = commit[:diff].gsub('```', "`\u200d``")

          truncated_message =
            if commit[:diff_truncated]
              "\n[... diff too long, it was truncated ...]\n"
            end

          body, linked_topics = auto_link_commits(commit[:body])
          linked_topics.merge! find_linked_commits(title)

          short_hash = "<small>sha: #{commit[:hash][0...8]}</small>"

          raw = "[excerpt]\n#{body}\n[/excerpt]\n\n```diff\n#{diff}\n#{truncated_message}```\n#{link} #{short_hash}"

          topic = find_topic_by_commit_hash(commit[:hash])

          if topic.present?
            if merged
              set_merged(topic)
            end
          else
            tags =
              if merged
                [SiteSetting.code_review_pending_tag]
              else
                [SiteSetting.code_review_unmerged_tag]
              end

            tags << SiteSetting.code_review_commit_tag

            post = PostCreator.create!(
              user,
              raw: raw,
              title: title,
              created_at: commit[:date],
              category: category_id,
              tags: tags,
              skip_validations: true,
            )

            TopicCustomField.create!(
              topic_id: post.topic_id,
              name: DiscourseCodeReview::COMMIT_HASH,
              value: commit[:hash]
            )

            linked_topics.values.each do |linked_topic|
              linked_topic.add_moderator_post(
                user,
                " #{post.topic.url}",
                bump: false,
                post_type: Post.types[:small_action],
                action_code: "followed_up"
              )
            end

            topic = post.topic
          end

          topic.id
        end
      end
    end

    private

    def find_topic_by_commit_hash(hash)
      Topic
        .where(
          id:
            TopicCustomField
              .where(
                name: DiscourseCodeReview::COMMIT_HASH,
                value: hash,
              )
              .limit(1)
              .select(:topic_id)
        ).first
    end

    def set_merged(topic)
      tags = topic.tags.pluck(:name)

      merged_tags = [
        SiteSetting.code_review_pending_tag,
        SiteSetting.code_review_approved_tag,
        SiteSetting.code_review_followup_tag
      ]

      if (tags & merged_tags).empty?
        tags << SiteSetting.code_review_pending_tag
        tags -= [SiteSetting.code_review_unmerged_tag]

        DiscourseTagging.tag_topic_by_names(
          topic,
          Discourse.system_user.guardian,
          tags
        )
      end
    end

    def find_linked_commits(text)
      result = {}

      shas = detect_shas(text)
      if shas.length > 0

        like_clause = shas.map { |sha| "f.value LIKE '#{sha}%'" }.join(' OR ')

        topics = Topic.select("topics.*, value AS sha")
          .joins("JOIN topic_custom_fields f ON topics.id = topic_id AND f.name = '#{DiscourseCodeReview::COMMIT_HASH}'")
          .where(like_clause)

        topics.each do |topic|

          lookup_shas = shas.select { |sha| topic.sha.start_with? sha }

          lookup_shas.each do |sha|
            result[sha] = topic
          end

        end
      end

      result
    end
  end
end
