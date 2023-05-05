# frozen_string_literal: true

require "rails_helper"

module DiscourseCodeReview
  describe Importer do
    def first_post_of(topic_id)
      Topic.find(topic_id).posts.order(:id).first
    end

    let(:parent_category) { Fabricate(:category) }
    let(:repo) { GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24) }

    it "creates categories with a description" do
      category = Category.find_by(id: Importer.new(repo).category_id)

      description =
        I18n.t("discourse_code_review.category_description", repo_name: "discourse/discourse").strip
      expect(category.description).to include(description)
      expect(category.topic.first_post.raw).to include(description)
    end

    it "mutes categories when code_review_default_mute_new_categories is true" do
      SiteSetting.code_review_default_mute_new_categories = true

      category = Category.find_by(id: Importer.new(repo).category_id)

      expect(SiteSetting.default_categories_muted.split("|").map(&:to_i)).to include(category.id)
      expect(category.parent_category_id).to eq(nil)
    end

    it "sets parent category when code_review_default_parent_category is persent" do
      SiteSetting.code_review_default_parent_category = parent_category.id

      category = Category.find_by(id: Importer.new(repo).category_id)

      expect(SiteSetting.default_categories_muted.split("|").map(&:to_i)).not_to include(
        category.id,
      )
      expect(category.parent_category_id).to eq(parent_category.id)
    end

    it "can look up a category id consistently" do
      # lets muck stuff up first ... and create a dupe category
      Category.create!(name: "discourse", user: Discourse.system_user)

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      id = Importer.new(repo).category_id

      expect(id).to be > 0
      expect(Importer.new(repo).category_id).to eq(id)
    end

    it "can cleanly associate old commits" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)

      diff = "```\nwith a diff"

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: diff,
        hash: "a1db15feadc7951d8a2b4ae63384babd6c568ae0",
      }

      repo.expects(:default_branch_contains?).with(commit[:hash]).returns(true)
      repo.expects(:followees).with(commit[:hash]).returns([])

      post = first_post_of(Importer.new(repo).import_commit(commit))

      commit[:hash] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      commit[:body] = "ab2787347ff (this is\nfollowing up on a1db15fe)"

      repo.expects(:default_branch_contains?).with(commit[:hash]).returns(true)
      repo.expects(:followees).with(commit[:hash]).returns([])

      post2 = first_post_of(Importer.new(repo).import_commit(commit))

      expect(post2.cooked).to include(post.topic.url)

      expect(post.topic.posts.length).to eq(1)
    end

    it "can handle complex imports" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)

      diff = "```\nwith a diff"

      body = <<~MD
      this is [amazing](http://amaz.ing)
      MD

      commit = {
        subject: "hello world",
        body: body,
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: diff,
        hash: SecureRandom.hex,
      }

      repo.expects(:default_branch_contains?).with(commit[:hash]).returns(true)
      repo.expects(:followees).with(commit[:hash]).returns([])

      post = first_post_of(Importer.new(repo).import_commit(commit))

      expect(post.cooked.scan("code").length).to eq(2)
      expect(post.excerpt).to eq("this is <a href=\"http://amaz.ing\">amazing</a>")
    end

    it "approves followed-up topics" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("a91843f0dc7b97e700dc85505404eafd62b7f8c5")
        .returns(true)
      repo.expects(:followees).with("a91843f0dc7b97e700dc85505404eafd62b7f8c5").returns([])
      repo
        .expects(:default_branch_contains?)
        .with("ca1208a63669d4d4ad7452367008d40fa090f645")
        .returns(true)
      repo
        .expects(:followees)
        .with("ca1208a63669d4d4ad7452367008d40fa090f645")
        .returns(["a91843f0dc7b97e700dc85505404eafd62b7f8c5"])

      SiteSetting.code_review_enabled = true

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "a91843f0dc7b97e700dc85505404eafd62b7f8c5",
      }

      followee = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)

      commit[:hash] = "ca1208a63669d4d4ad7452367008d40fa090f645"
      follower = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).to include(SiteSetting.code_review_approved_tag)
    end

    it "approves followed-up topics with partial hashes" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("5ff6c10320cab7ef82ecda40c57cfb9e539b7e72")
        .returns(true)
      repo.expects(:followees).with("5ff6c10320cab7ef82ecda40c57cfb9e539b7e72").returns([])
      repo
        .expects(:default_branch_contains?)
        .with("dbfb2a1e11b6a4f33d35b26885193774e7ab9362")
        .returns(true)
      repo.expects(:followees).with("dbfb2a1e11b6a4f33d35b26885193774e7ab9362").returns(["5ff6c10"])

      SiteSetting.code_review_enabled = true

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "5ff6c10320cab7ef82ecda40c57cfb9e539b7e72",
      }

      followee = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)

      commit[:hash] = "dbfb2a1e11b6a4f33d35b26885193774e7ab9362"
      follower = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).to include(SiteSetting.code_review_approved_tag)
    end

    it "does not extract followees from revert commits" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("154f503d2e99f904356b52f2fae9edcc495708fa")
        .returns(true)
      repo.expects(:followees).with("154f503d2e99f904356b52f2fae9edcc495708fa").returns([])
      repo
        .expects(:default_branch_contains?)
        .with("d2a7f29595786376a3010cb7e320d66f5b8d60ef")
        .returns(true)
      repo.expects(:followees).with("d2a7f29595786376a3010cb7e320d66f5b8d60ef").returns([])

      SiteSetting.code_review_enabled = true

      commit = {
        subject: "hello world",
        body: "this is the body",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "154f503d2e99f904356b52f2fae9edcc495708fa",
      }

      followee = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)

      commit[:hash] = "d2a7f29595786376a3010cb7e320d66f5b8d60ef"
      follower = Topic.find(Importer.new(repo).import_commit(commit))

      expect(followee.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)
    end

    it "does not parse emojis in commit message" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("154f503d2e99f904356b52f2fae9edcc495708fa")
        .returns(true)
      repo.expects(:followees).with("154f503d2e99f904356b52f2fae9edcc495708fa").returns([])

      commit = {
        subject: "hello world",
        body: "this is the body\nwith an emoji :)",
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "154f503d2e99f904356b52f2fae9edcc495708fa",
      }

      topic = Topic.find(Importer.new(repo).import_commit(commit))
      expect(topic.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)
      expect(topic.posts.pick(:raw)).to include("with an emoji :)")
    end

    it "escapes Git trailers" do
      topic = Fabricate(:topic)
      topic.custom_fields[
        DiscourseCodeReview::COMMIT_HASH
      ] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      topic.save
      CommitTopic.create!(topic_id: topic.id, sha: "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb")

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("154f503d2e99f904356b52f2fae9edcc495708fa")
        .returns(true)
      repo.expects(:followees).with("154f503d2e99f904356b52f2fae9edcc495708fa").returns([])

      body = <<~TEXT
      Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce et
      porttitor nibh, quis pellentesque mauris. Phasellus ornare auctor
      imperdiet. In id ex in nibh gravida commodo nec eget ipsum. Mauris
      interdum ex nisi, quis sollicitudin est ornare venenatis.

      Integer vitae eros sit amet magna aliquet accumsan eget a est. In at mi
      ligula. Duis dolor velit, efficitur sed dapibus ac, volutpat eget quam.

      Sed eget imperdiet nulla. In molestie, urna eget tincidunt pulvinar,
      augue massa lobortis magna, quis semper ante leo sed est. Aenean ornare
      feugiat magna at ultricies. Fusce eget blandit magna, sit amet ornare
      orci. Nulla lobortis orci augue. In eu diam sed tortor suscipit mollis.

      Reported-and-tested-by: A <a@example.com>
      Reviewed-by: B <b@example.com>
      Cc: C <c@example.com>
      Cc: D <d@example.com>
      Cc: E <e@example.com>
      Signed-off-by: F <f@example.com>
      Commit: dbbadb5c357bc23daf1fa732f8670e55dc28b7cb
      TEXT

      commit = {
        subject: "hello world",
        body: body,
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "154f503d2e99f904356b52f2fae9edcc495708fa",
      }

      topic = Topic.find(Importer.new(repo).import_commit(commit))
      expect(topic.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)
      expect(topic.posts.pick(:cooked)).to match_html <<~HTML
      <div class="excerpt">
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Fusce et<br>
        porttitor nibh, quis pellentesque mauris. Phasellus ornare auctor<br>
        imperdiet. In id ex in nibh gravida commodo nec eget ipsum. Mauris<br>
        interdum ex nisi, quis sollicitudin est ornare venenatis.</p>

        <p>Integer vitae eros sit amet magna aliquet accumsan eget a est. In at mi<br>
        ligula. Duis dolor velit, efficitur sed dapibus ac, volutpat eget quam.</p>

        <p>Sed eget imperdiet nulla. In molestie, urna eget tincidunt pulvinar,<br>
        augue massa lobortis magna, quis semper ante leo sed est. Aenean ornare<br>
        feugiat magna at ultricies. Fusce eget blandit magna, sit amet ornare<br>
        orci. Nulla lobortis orci augue. In eu diam sed tortor suscipit mollis.</p>

        <pre><code class="lang-auto">Reported-and-tested-by: A &lt;a@example.com&gt;
        Reviewed-by: B &lt;b@example.com&gt;
        Cc: C &lt;c@example.com&gt;
        Cc: D &lt;d@example.com&gt;
        Cc: E &lt;e@example.com&gt;
        Signed-off-by: F &lt;f@example.com&gt;
        Commit: dbbadb5c357bc23daf1fa732f8670e55dc28b7cb</code></pre>
      </div>

      <pre><code class="lang-diff">`‍``
      with a diff
      </code></pre>

      <p><a href="https://github.com/discourse/discourse/commit/154f503d2e99f904356b52f2fae9edcc495708fa">GitHub</a><br>
      <small>sha: 154f503d2e99f904356b52f2fae9edcc495708fa</small></p>
      HTML
    end

    it "escapes Git trailers only if present in last paragraph" do
      topic = Fabricate(:topic)
      topic.custom_fields[
        DiscourseCodeReview::COMMIT_HASH
      ] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      topic.save
      CommitTopic.create!(topic_id: topic.id, sha: "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb")

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("154f503d2e99f904356b52f2fae9edcc495708fa")
        .returns(true)
      repo.expects(:followees).with("154f503d2e99f904356b52f2fae9edcc495708fa").returns([])

      body = <<~TEXT
      Commit title

      example: https://example.com

      Lorem ipsum
      TEXT

      commit = {
        subject: "hello world",
        body: body,
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "154f503d2e99f904356b52f2fae9edcc495708fa",
      }

      topic = Topic.find(Importer.new(repo).import_commit(commit))
      expect(topic.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)
      expect(topic.posts.pick(:cooked)).to match_html <<~HTML
        <div class="excerpt">
        <p>Commit title</p>
        <p>example: <a href="https://example.com">https://example.com</a></p>
        <p>Lorem ipsum</p>
        </div>
        <pre><code class="lang-diff">`‍``
        with a diff
        </code></pre>
        <p><a href="https://github.com/discourse/discourse/commit/154f503d2e99f904356b52f2fae9edcc495708fa">GitHub</a><br>
        <small>sha: 154f503d2e99f904356b52f2fae9edcc495708fa</small></p>
      HTML
    end

    it "escapes Git trailers only if it starts at the beginning of the line" do
      topic = Fabricate(:topic)
      topic.custom_fields[
        DiscourseCodeReview::COMMIT_HASH
      ] = "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb"
      topic.save
      CommitTopic.create!(topic_id: topic.id, sha: "dbbadb5c357bc23daf1fa732f8670e55dc28b7cb")

      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("154f503d2e99f904356b52f2fae9edcc495708fa")
        .returns(true)
      repo.expects(:followees).with("154f503d2e99f904356b52f2fae9edcc495708fa").returns([])

      body = <<~TEXT
      Commit title

         example: https://example.com
      TEXT

      commit = {
        subject: "hello world",
        body: body,
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "154f503d2e99f904356b52f2fae9edcc495708fa",
      }

      topic = Topic.find(Importer.new(repo).import_commit(commit))
      expect(topic.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)
      expect(topic.posts.pick(:cooked)).to match_html <<~HTML
        <div class="excerpt">
        <p>Commit title</p>
        <p>   example: <a href="https://example.com">https://example.com</a></p>
        </div>
        <pre><code class="lang-diff">`‍``
        with a diff
        </code></pre>
        <p><a href="https://github.com/discourse/discourse/commit/154f503d2e99f904356b52f2fae9edcc495708fa">GitHub</a><br>
        <small>sha: 154f503d2e99f904356b52f2fae9edcc495708fa</small></p>
      HTML
    end

    it "escapes correct Git trailers" do
      repo = GithubRepo.new("discourse/discourse", Octokit::Client.new, nil, repo_id: 24)
      repo
        .expects(:default_branch_contains?)
        .with("154f503d2e99f904356b52f2fae9edcc495708fa")
        .returns(true)
      repo.expects(:followees).with("154f503d2e99f904356b52f2fae9edcc495708fa").returns([])

      body = <<~TEXT
      Discourse

      http://discourse.org
      TEXT

      commit = {
        subject: "hello world",
        body: body,
        email: "sam@sam.com",
        github_login: "sam",
        github_id: "111",
        date: 1.day.ago,
        diff: "```\nwith a diff",
        hash: "154f503d2e99f904356b52f2fae9edcc495708fa",
      }

      topic = Topic.find(Importer.new(repo).import_commit(commit))
      expect(topic.tags.pluck(:name)).not_to include(SiteSetting.code_review_approved_tag)
      expect(topic.posts.pick(:cooked)).to match_html <<~HTML
      <div class="excerpt">
        <p>Discourse</p>
        <p><a href="http://discourse.org">http://discourse.org</a></p>
      </div>

      <pre><code class="lang-diff">`‍``
        with a diff
      </code></pre>

      <p><a href="https://github.com/discourse/discourse/commit/154f503d2e99f904356b52f2fae9edcc495708fa">GitHub</a><br>
      <small>sha: 154f503d2e99f904356b52f2fae9edcc495708fa</small></p>
      HTML
    end
  end
end
