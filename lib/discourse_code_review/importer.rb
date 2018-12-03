module DiscourseCodeReview
  class Importer
    attr_reader :github_repo

    GithubRepoName = "GitHub Repo Name"

    def initialize(github_repo)
      @github_repo = github_repo
    end

    def category_id
      @category_id ||=
        begin
          id = Category.where(<<~SQL, name: GithubRepoName, value: github_repo.name).order(:id).pluck(:id).first
            id IN (SELECT category_id FROM category_custom_fields WHERE name = :name AND value = :value)
          SQL
          if !id
            Category.transaction do
              short_name = find_category_name(github_repo.name.split("/").last)
              category = Category.create!(name: short_name, user: Discourse.system_user)
              category.custom_fields[GithubRepoName] = github_repo.name
              category.save_custom_fields
              id = category.id
            end
          end
          id
        end
    end

    def import_commits
      github_repo.commits_since.each do |commit|
        import_commit(commit)
      end
    end

    def import_commit(commit)
      link = <<~LINK
        [<small>GitHub</small>](https://github.com/#{github_repo.name}/commit/#{commit[:hash]})
      LINK

      title = commit[:subject]
      # we add a unicode zero width joiner so code block is not corrupted
      diff = commit[:diff].gsub('```', "`\u200d``")
      raw = commit[:body] + "\n\n```diff\n#{diff}\n```\n#{link}"

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
          created_at: commit[:date],
          category: category_id,
          tags: [SiteSetting.code_review_pending_tag],
          skip_validations: true,
        )

        TopicCustomField.create!(
          topic_id: post.topic_id,
          name: DiscourseCodeReview::CommitHash,
          value: commit[:hash]
        )

        github_repo.last_commit = commit[:hash]

        post
      end
    end

    def import_comments
      page = github_repo.current_comment_page

      while true
        comments = github_repo.commit_comments(page)

        break if comments.blank?

        comments.each do |comment|
          import_comment(comment)
        end

        github_repo.current_comment_page = page
        page += 1
      end
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

    protected

    def import_comment(comment)

      # skip if we already have the comment
      return if PostCustomField.exists?(name: DiscourseCodeReview::GithubId, value: comment[:id])

      # do we have the commit?
      if topic_id = TopicCustomField.where(name: DiscourseCodeReview::CommitHash, value: comment[:commit_hash]).pluck(:topic_id).first
        login = comment[:login] || "unknown"
        user = ensure_user(email: "#{login}@fake.github.com", name: login, github_login: login)

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

        PostCreator.create!(
          user,
          raw: context + comment[:body],
          skip_validations: true,
          created_at: comment[:created_at],
          topic_id: topic_id,
          custom_fields: { DiscourseCodeReview::GithubId => comment[:id] }
        )
      end
    end

    def find_category_name(name)
      if Category.where(name: name).exists?
        name += SecureRandom.hex
      else
        name
      end
    end
  end
end
