# frozen_string_literal: true

module DiscourseCodeReview
  module State::CommitTopics
    class << self
      def auto_link_commits(text, doc = nil)
        linked_commits = find_linked_commits(text)
        if (linked_commits.length > 0)
          doc ||= Nokogiri::HTML5::fragment(PrettyText.cook(text, disable_emojis: true))
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

      def ensure_commit_comment(user:, topic_id:, comment:)
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

        custom_fields = {}
        custom_fields[DiscourseCodeReview::COMMENT_PATH] = comment[:path] if comment[:path].present?
        custom_fields[DiscourseCodeReview::COMMENT_POSITION] = comment[:position] if comment[:position].present?

        DiscourseCodeReview::State::Helpers.ensure_post_with_nonce(
          created_at: comment[:created_at],
          custom_fields: custom_fields,
          nonce_name: DiscourseCodeReview::GITHUB_ID,
          nonce_value: comment[:id],
          raw: context + comment[:body],
          skip_validations: true,
          topic_id: topic_id,
          user: user,
        )
      end

      def ensure_commit(commit:, merged:, repo_name:, user:, category_id:, followees:)
        DistributedMutex.synchronize('code-review:create-commit-topic') do
          ActiveRecord::Base.transaction(requires_new: true) do
            link = <<~LINK
              [GitHub](https://github.com/#{repo_name}/commit/#{commit[:hash]})
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

            hash_html = "<small>sha: #{commit[:hash]}</small>"

            raw = "[excerpt]\n#{body}\n[/excerpt]\n\n```diff\n#{diff}\n#{truncated_message}```\n#{link} #{hash_html}"

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

              truncated_title = title
              iterations = 0
              while Topic.fancy_title(truncated_title).length > Topic.max_fancy_title_length
                if iterations >= 3
                  truncated_title = "Automatic title for commit #{commit[:hash][0...8]}"
                  break
                end
                iterations += 1
                truncation = [10, Topic.max_fancy_title_length - iterations * 50].max
                truncated_title = truncated_title.truncate(truncation)
              end

              post = PostCreator.create!(
                user,
                raw: raw,
                title: truncated_title,
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

              CommitTopic.create!(
                topic_id: post.topic_id,
                sha: commit[:hash],
              )

              if followees.present? && SiteSetting.code_review_auto_approve_followed_up_commits
                followee_topics =
                  Topic
                    .joins(:code_review_commit_topic)
                    .where(
                      'code_review_commit_topics.sha SIMILAR TO ?',
                      "(#{followees.join('|')})%",
                    )

                followee_topics.each do |followee_topic|
                  DiscourseCodeReview::State::CommitApproval.followed_up(
                    followee_topic,
                    post.topic,
                  )
                end
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
          .joins(:code_review_commit_topic)
          .where(code_review_commit_topics: { sha: hash })
          .first
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

          like_clause = shas.map { |sha| "f.sha LIKE '#{sha}%'" }.join(' OR ')

          topics =
            Topic.select("topics.*, sha")
              .joins("JOIN code_review_commit_topics f ON topics.id = topic_id")
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
end
