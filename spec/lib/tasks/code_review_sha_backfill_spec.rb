# frozen_string_literal: true

require 'rails_helper'

describe "tasks/code_review_sha_backfill" do
  before do
    Rake::Task.clear
    Discourse::Application.load_tasks
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
      post.rebake!
    end

    it "updates the post raw with the post revisor to have the full sha" do
      original_raw = post.raw
      Rake::Task['discourse_code_review:full_sha_backfill'].invoke
      post.reload

      expect(post.raw.chomp).to eq(original_raw.gsub("sha: c187ede3", "sha: c187ede3c67f23478bc2d3c20187bd98ac025b9e").chomp)
      revision = PostRevision.last
      expect(revision.modifications["edit_reason"]).to eq([nil, "discourse code review full sha backfill"])
    end

    it "is idempotent based on revision reason" do
      Rake::Task['discourse_code_review:full_sha_backfill'].invoke
      revision = PostRevision.last
      expect(revision.modifications["edit_reason"]).to eq([nil, "discourse code review full sha backfill"])

      Rake::Task['discourse_code_review:full_sha_backfill'].reenable
      Rake::Task['discourse_code_review:full_sha_backfill'].invoke

      expect(PostRevision.count).to eq(1)
    end
  end
end
