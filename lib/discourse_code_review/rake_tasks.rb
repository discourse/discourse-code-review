# frozen_string_literal: true

module DiscourseCodeReview
  class RakeTasks
    def self.define_tasks
      Rake::Task.define_task code_review_delete_user_github_access_tokens: :environment do
        num_deleted = UserCustomField.where(name: 'github user token').delete_all
        puts "deleted #{num_deleted} user_custom_fields"
      end

      Rake::Task.define_task code_review_tag_commits: :environment do
        topics = Topic.joins(:code_review_commit_topic).to_a

          puts "Tagging #{topics.size} topics"

          topics.each do |topic|
            DiscourseTagging.tag_topic_by_names(
              topic,
              Discourse.system_user.guardian,
              [SiteSetting.code_review_commit_tag],
              append: true
            )
          end
      end

      Rake::Task.define_task code_review_full_sha_backfill: :environment do
        posts_with_commit = Post
          .joins("INNER JOIN topics ON topics.id = posts.topic_id")
          .joins("INNER JOIN code_review_commit_topics ON topics.id = code_review_commit_topics.topic_id")
          .includes(topic: :code_review_commit_topic)
          .where("
            topics.deleted_at IS NULL AND
            posts.deleted_at IS NULL AND
            posts.post_number = 1 AND
            posts.raw ~ 'sha: [0-9a-f]{6,10}' AND
            posts.raw !~ 'sha: [0-9a-f]{11,60}'")

        total = posts_with_commit.count
        incr = 0

        puts "Found #{total} posts with a commit sha from the discourse-code-review plugin."

        posts_with_commit.find_each do |post_with_commit|
          puts "Replacing sha in post #{post_with_commit.id}..."

          full_git_sha = post_with_commit.topic.code_review_commit_topic.sha
          new_raw = post_with_commit.raw.gsub(/sha: [0-9a-f]{6,10}\b/, "sha: #{full_git_sha}")

          if new_raw == post_with_commit.raw
            puts "Nothing to change for post #{post_with_commit.id}, continuing. (new raw same as old raw)"
            incr += 1
            puts "Completed #{incr}/#{total}."
            next
          end

          post_with_commit.update(raw: new_raw)
          post_with_commit.rebake!

          incr += 1
          puts "Completed #{incr}/#{total}."
        end

        puts "All complete."
      end
    end
  end
end
