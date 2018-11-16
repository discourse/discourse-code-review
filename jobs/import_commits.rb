module Jobs

  class ::DiscourseCodeReview::ImportCommits < Jobs::Scheduled
    every 1.minute

    def execute(args = nil)

      return unless SiteSetting.code_review_enabled && SiteSetting.code_review_github_repo.present?

      DiscourseCodeReview.commits_since.each do |commit|

        title = commit[:subject]
        raw = commit[:body] + "\n\n```diff\n#{commit[:diff]}\n```"

        user = ensure_user(
          email: commit[:email],
          name: commit[:name],
          github_login: commit[:author_login],
          github_id: commit[:author_id]
        )

        if !TopicCustomField.exists?(name: DiscourseCodeReview::CommitHash, value: commit[:hash])

          post = PostCreator.create!(
            user,
            raw: raw,
            title: title,
            skip_validations: true,
            created_at: commit[:date],
            category: SiteSetting.code_review_pending_category_id
          )

          TopicCustomField.create!(
            topic_id: post.topic_id,
            name: DiscourseCodeReview::CommitHash,
            value: commit[:hash]
          )

          DiscourseCodeReview.last_commit = commit[:hash]
        end
      end

      import_comments
    end

    def ensure_user(email:, name:, github_login: nil, github_id: nil)
      user = nil

      if github_id
        if user_id = UserCustomField.where(name: DiscourseCodeReview::GithubId, value: github_id).pluck(:user_id).first
          user = User.find_by(id: user_id)
        end
      end

      if !user && github_login
        if user_id = UserCustomField.where(name: DiscourseCodeReview::GithubLogin, value: github_login).pluck(:user_id).first
          user = User.find_by(id: user_id)
        end
      end

      user ||= User.find_by_email(email)

      if !user
        username = UserNameSuggester.sanitize_username(github_login || name)
        begin
          user = User.create!(
            email: email,
            username: UserNameSuggester.suggest(username.presence || email),
            name: name.presence || User.suggest_name(email),
            staged: true
          )
        end
      end

      if github_login

        rel = UserCustomField.where(name: DiscourseCodeReview::GithubLogin, value: github_login)
        existing = rel.pluck(:user_id)

        if existing != [user.id]
          rel.destroy_all
          UserCustomField.create!(name: DiscourseCodeReview::GithubLogin, value: github_login, user_id: user.id)
        end
      end

      if github_id

        rel = UserCustomField.where(name: DiscourseCodeReview::GithubId, value: github_id)
        existing = rel.pluck(:user_id)

        if existing != [user.id]
          rel.destroy_all
          UserCustomField.create!(name: DiscourseCodeReview::GithubId, value: github_id, user_id: user.id)
        end
      end
      user
    end

    def import_comments
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
        user = ensure_user(email: "#{login}@fake.github.com", name: login, github_login: login)

        PostCreator.create!(
          user,
          raw: comment[:body],
          skip_validations: true,
          created_at: comment[:created_at],
          topic_id: topic_id,
          custom_fields: { DiscourseCodeReview::GithubId => comment[:id] }
        )
      end
    end

  end
end
