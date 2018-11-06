module Jobs

  class ::DiscourseCodeReview::ImportCommits < Jobs::Scheduled
    every 1.minute

    def execute(args = nil)

      DiscourseCodeReview.commits_since.each do |commit|

        title = commit[:subject]
        raw = commit[:body] + "\n\n```diff\n#{commit[:diff]}\n```"

        user = User.find_by_email(commit[:email])
        if !user
          name = commit[:name]
          username = UserNameSuggester.sanitize_username(name)
          email = commit[:email]
          begin
            user = User.create!(
              email: email,
              username: UserNameSuggester.suggest(username.presence || email),
              name: name.presence || User.suggest_name(email),
              staged: true
            )
          end
        end

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

  end
end
