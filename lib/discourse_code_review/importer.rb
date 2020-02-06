# frozen_string_literal: true

module DiscourseCodeReview
  class Importer
    attr_reader :github_repo

    def initialize(github_repo)
      @github_repo = github_repo
    end

    def self.sync_commit(sha)
      client = DiscourseCodeReview.octokit_client
      GithubCategorySyncer.each_repo_name do |repo_name|
        repo = GithubRepo.new(repo_name, client)
        importer = Importer.new(repo)

        if commit = repo.commit(sha)
          importer.sync_commit(commit)
          return repo_name
        end
      end

      nil
    end

    def self.sync_commit_from_repo(repo_name, sha)
      client = DiscourseCodeReview.octokit_client
      repo = GithubRepo.new(repo_name, client)
      importer = Importer.new(repo)
      importer.sync_commit_sha(sha)
    end

    def category_id
      @category_id ||=
        GithubCategorySyncer.ensure_category(
          repo_name: github_repo.name
        ).id
    end

    def sync_merged_commits
      last_commit = nil
      github_repo.commits_since.each do |commit|
        sync_commit(commit)

        github_repo.last_commit = commit[:hash]
      end
    end

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

    def sync_commit_sha(commit_sha)
      commit = github_repo.commit(commit_sha)
      sync_commit(commit)
    end

    def sync_commit(commit)
      topic_id = import_commit(commit)
      import_comments(topic_id, commit[:hash])
      topic_id
    end

    def import_commit(commit)
      merged = github_repo.master_contains?(commit[:hash])

      link = <<~LINK
        [<small>GitHub</small>](https://github.com/#{github_repo.name}/commit/#{commit[:hash]})
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

      user = DiscourseCodeReview.github_user_syncer.ensure_user(
        email: commit[:email],
        name: commit[:name],
        github_login: commit[:author_login],
        github_id: commit[:author_id]
      )

      ensure_commit(
        commit: commit,
        merged: merged,
        user: user,
        title: title,
        raw: raw,
        category_id: category_id,
        linked_topics: linked_topics
      )
    end

    def import_comments(topic_id, commit_sha)
      github_repo.commit_comments(commit_sha).each do |comment|
        ensure_commit_comment(topic_id, comment)
      end
    end

    private

    def ensure_commit(commit:, merged:, user:, title:, raw:, category_id:, linked_topics:)
      topic_id =
        TopicCustomField
          .where(
            name: DiscourseCodeReview::COMMIT_HASH,
            value: commit[:hash]
          )
          .limit(1)
          .pluck(:topic_id)
          .first

      if topic_id.present?
        if merged
          topic = Topic.find(topic_id)
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

        topic_id = post.topic_id
      end

      topic_id
    end

    def ensure_commit_comment(topic_id, comment)
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
