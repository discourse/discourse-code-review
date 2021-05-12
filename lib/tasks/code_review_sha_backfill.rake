# frozen_string_literal: true

desc "backfill full git commit sha in topic OPs"
task 'discourse_code_review:full_sha_backfill' => :environment do
  posts_with_commit = Post
    .joins("INNER JOIN topics ON topics.id = posts.topic_id")
    .joins("INNER JOIN topic_custom_fields ON topics.id = topic_custom_fields.topic_id")
    .joins("LEFT JOIN post_revisions ON post_revisions.post_id = posts.id")
    .includes(topic: :_custom_fields)
    .includes(:post_revisions)
    .where("topic_custom_fields.name = '#{DiscourseCodeReview::COMMIT_HASH}' AND
            topics.deleted_at IS NULL AND
            posts.deleted_at IS NULL AND
            posts.post_number = 1 AND
            posts.raw LIKE '%sha: %'")

  total = posts_with_commit.count
  incr = 0

  puts "Found #{total} posts with a commit sha from the discourse-code-review plugin."

  posts_with_commit.find_each do |post_with_commit|
    puts "Replacing sha in post #{post_with_commit.id}..."

    if post_with_commit.post_revisions.find { |rev|
      rev.modifications["edit_reason"].include?("discourse code review full sha backfill")
    }
      puts "Nothing to change for post #{post_with_commit.id}, continuing. (already revised with full sha)"
      incr += 1
      puts "Completed #{incr}/#{total}."
      next
    end

    full_git_sha = post_with_commit.topic.custom_fields[DiscourseCodeReview::COMMIT_HASH]
    doc = Nokogiri::HTML5::fragment(post_with_commit.raw)
    doc.search("small").each do |small_element|
      if small_element.content.include?("sha: ")
        small_element.content = "sha: #{full_git_sha}"
      end
    end

    new_raw = doc.to_s
    if new_raw == post_with_commit.raw
      puts "Nothing to change for post #{post_with_commit.id}, continuing. (new raw same as old raw)"
      incr += 1
      puts "Completed #{incr}/#{total}."
      next
    end

    PostRevisor.new(post_with_commit).revise!(
      Discourse.system_user,
      {
        raw: new_raw,
        edit_reason: "discourse code review full sha backfill"
      },
      skip_validations: true,
      bypass_bump: true
    )

    incr += 1
    puts "Completed #{incr}/#{total}."
  end

  puts "All complete."
end
