# frozen_string_literal: true

require 'rails_helper'

describe "tasks/code_review_sha_backfill" do
  before do
    Rake::Task.clear
    Discourse::Application.load_tasks
    DiscourseCodeReview::RakeTasks.define_tasks
  end

  def raw
    <<~RAW
    [excerpt]
    This is the commit message.

    And some more info.
[/excerpt]

```diff
git diff data
@@ -68,10 +68,10 @@
some code
```
[GitHub](https://github.com/discourse/discourse/commit/c187ede3c67f23478bc2d3c20187bd98ac025b9e)
 <small>sha: c187ede3</small>
    RAW
  end

  describe "discourse_code_review:full_sha_backfill" do
    let(:topic) { Fabricate(:topic) }
    let(:post) { Fabricate(:post, topic: topic, raw: raw) }

    before do
      topic.custom_fields[DiscourseCodeReview::COMMIT_HASH] = 'c187ede3c67f23478bc2d3c20187bd98ac025b9e'
      topic.save_custom_fields
      DiscourseCodeReview::CommitTopic.create!(topic_id: topic.id, sha: 'c187ede3c67f23478bc2d3c20187bd98ac025b9e')
      post.rebake!
      Rake::Task['code_review_full_sha_backfill'].reenable
    end

    it "updates the post raw with the post revisor to have the full sha" do
      original_raw = post.raw
      capture_stdout do
        Rake::Task['code_review_full_sha_backfill'].invoke
      end
      post.reload

      expect(post.raw.chomp).to eq(original_raw.gsub("sha: c187ede3", "sha: c187ede3c67f23478bc2d3c20187bd98ac025b9e").chomp)
    end

    it "is idempotent based on raw not changing and the query not getting longer shas" do
      capture_stdout do
        Rake::Task['code_review_full_sha_backfill'].invoke
      end
      post_baked_at = post.reload.baked_at
      Rake::Task['code_review_full_sha_backfill'].reenable

      capture_stdout do
        Rake::Task['code_review_full_sha_backfill'].invoke
      end
      expect(post.reload.baked_at).to eq_time(post_baked_at)
    end
  end
end
