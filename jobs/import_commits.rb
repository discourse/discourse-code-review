module Jobs

  class ::DiscourseCodeReview::ImportCommits < Jobs::Scheduled
    every 1.minute

    def execute(args = nil)

      DiscourseCodeReview.commits_since.each do |commit|

        title = commit[:subject]
        raw = commit[:body] + "\n\n```diff\n#{commit[:diff]}\n```"

        user = ensure_user(email: commit[:email], name: commit[:name])

        if !TopicCustomField.exists?(name: DiscourseCodeReview::CommitHash, value: commit[:hash])

          post = PostCreator.create!(
            user,
            raw: raw,
            title: title,
            skip_validations: true,
            created_at: commit[:date]
          )

          TopicCustomField.create!(
            topic_id: post.topic_id,
            name: DiscourseCodeReview::CommitHash,
            value: commit[:hash]
          )

          DiscourseCodeReview.last_commit = commit[:hash]
        end
      end

    end

    def ensure_user(email:, name:)
      user = User.find_by_email(email)
      if !user
        username = UserNameSuggester.sanitize_username(name)
        begin
          user = User.create!(
            email: email,
            username: UserNameSuggester.suggest(username.presence || email),
            name: name.presence || User.suggest_name(email),
            staged: true
          )
        end
      end
      user
    end

    def import_comments
      # 140 is a good page for Discourse :)
      # for testing
      page = DiscourseCodeReview.current_comment_page

      while true
        comments = DiscourseCodeReview.commit_comments(page)

        break if comments.blank?

        comments.each do |comment|
          import_comment(comment)
        end

        DiscourseCodeReview.current_comment_page = page
        page += 1
      end
    end

    def import_comment(comment)

      # skip if we already have the comment
      return if PostCustomField.exists?(name: DiscourseCodeReview::GithubId, value: comment[:id])

      # do we have the commit?
      if topic_id = TopicCustomField.where(name: DiscourseCodeReview::CommitHash, value: comment[:commit_hash]).pluck(:topic_id).first
        login = comment[:login] || "unknown"
        user = ensure_user(email: "#{login}@fake.github.com", name: login)

        post = PostCreator.create!(
          user,
          raw: comment[:body],
          skip_validations: true,
          created_at: comment[:created_at],
          topic_id: topic_id
        )

        PostCustomField.create!(post_id: post.id, name: DiscourseCodeReview::GithubId, value: comment[:id])
      end
    end

  end
end
