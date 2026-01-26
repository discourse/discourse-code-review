# frozen_string_literal: true

class MockGithubPRService
  def initialize(**opts)
    @opts = opts
  end

  def pull_requests(repo_name)
    @opts.fetch(:pull_requests, {}).fetch(repo_name, [])
  end

  def associated_pull_requests(repo_name, commit_sha)
    @opts.fetch(:associated_pull_requests, {}).fetch([repo_name, commit_sha], [])
  end

  def pull_request_data(pr)
    @opts.fetch(:pull_request_data, {}).fetch(pr, [])
  end

  def pull_request_events(pr)
    @opts.fetch(:pull_request_events, {}).fetch(pr, [])
  end
end

class MockGithubUserQuerier
  def initialize(**opts)
    @opts = opts
  end

  def get_user_email(github_login)
    @opts.fetch(:emails, {}).fetch(github_login, nil)
  end
end

describe DiscourseCodeReview::GithubPRSyncer do
  let!(:pr) do
    DiscourseCodeReview::PullRequest.new(owner: "owner", name: "name", issue_number: 101)
  end

  let!(:actor) { DiscourseCodeReview::Actor.new(github_login: "coder1234") }

  let!(:pr_data) do
    DiscourseCodeReview::PullRequestData.new(
      title: "Title",
      body: "Body",
      github_id: "Pull request github id",
      created_at: Time.parse("2000-01-01 00:00:00 UTC"),
      author: actor,
    )
  end

  let!(:empty_user_querier) { MockGithubUserQuerier.new() }

  define_method(:create_pr_syncer) do |pr_service, user_querier|
    DiscourseCodeReview::GithubPRSyncer.new(
      pr_service,
      DiscourseCodeReview::GithubUserSyncer.new(user_querier),
    )
  end

  let!(:event_info) do
    DiscourseCodeReview::PullRequestEventInfo.new(
      github_id: "github event id",
      created_at: Time.parse("2000-01-01 01:00:00 UTC"),
      actor: actor,
    )
  end

  let!(:event_info2) do
    DiscourseCodeReview::PullRequestEventInfo.new(
      github_id: "second github event id",
      created_at: Time.parse("2000-01-01 02:00:00 UTC"),
      actor: actor,
    )
  end

  define_method(:last_topic) { Topic.order("id DESC").first }

  define_method(:first_post_of_last_topic) { last_topic.posts.first }

  define_method(:last_post_of_last_topic) { last_topic.posts.last }

  fab!(:category) do
    DiscourseCodeReview::State::GithubRepoCategories.ensure_category(
      repo_name: "owner/name",
      repo_id: "24",
    )
  end

  before { User.set_callback(:create, :after, :ensure_in_trust_level_group) }
  after { User.skip_callback(:create, :after, :ensure_in_trust_level_group) }

  describe "#sync_pull_request" do
    context "when there are no events" do
      let!(:syncer) do
        pr_service = MockGithubPRService.new(pull_request_data: { pr => pr_data })

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates a topic" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Topic.count }.by(1)
      end

      it "creates a topic idempotently" do
        syncer.sync_pull_request("owner/name", 101)

        expect { syncer.sync_pull_request("owner/name", 101) }.not_to change { Topic.count }
      end

      it "creates one post" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(1)
      end

      it "puts the github url in the first post" do
        syncer.sync_pull_request("owner/name", 101)

        expect(first_post_of_last_topic.raw).to include("https://github.com/owner/name/pull/101")
      end

      it "puts the original comment in the first post" do
        syncer.sync_pull_request("owner/name", 101)

        expect(first_post_of_last_topic.raw).to include(pr_data.body)
      end
    end

    context "when there is a close event" do
      let!(:closed_event) { DiscourseCodeReview::PullRequestEvent.create(:closed) }

      let!(:syncer) do
        pr_service =
          MockGithubPRService.new(
            pull_request_data: {
              pr => pr_data,
            },
            pull_request_events: {
              pr => [[event_info, closed_event]],
            },
          )

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates closed posts" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(2)

        expect(last_post_of_last_topic.action_code).to eq("closed.enabled")
      end

      it "creates closed posts idempotently" do
        syncer.sync_pull_request("owner/name", 101)

        expect { syncer.sync_pull_request("owner/name", 101) }.not_to change { Post.count }
      end

      it "closes the topic" do
        syncer.sync_pull_request("owner/name", 101)

        expect(last_topic).to be_closed
      end
    end

    context "when the events contain an commit comment" do
      fab!(:commit_topic, :topic)

      let!(:commit_thread_started_event) do
        DiscourseCodeReview::PullRequestEvent.create(:commit_thread_started, commit_sha: "deadbeef")
      end

      let!(:syncer) do
        pr_service =
          MockGithubPRService.new(
            pull_request_data: {
              pr => pr_data,
            },
            pull_request_events: {
              pr => [[event_info, commit_thread_started_event]],
            },
          )

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates posts that link to commit discussion threads" do
        DiscourseCodeReview::Importer
          .expects(:sync_commit_from_repo)
          .with("owner/name", "deadbeef")
          .returns(commit_topic.id)

        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(2)

        expect(last_post_of_last_topic.raw).to include(commit_topic.url)
      end

      it "creates posts that link to commit discussion threads idempotently" do
        DiscourseCodeReview::Importer
          .stubs(:sync_commit_from_repo)
          .with("owner/name", "deadbeef")
          .returns(commit_topic.id)

        syncer.sync_pull_request("owner/name", 101)

        expect { syncer.sync_pull_request("owner/name", 101) }.not_to change { Post.count }
      end
    end

    context "when the events contain an issue comment" do
      let!(:issue_comment) do
        DiscourseCodeReview::PullRequestEvent.create(:issue_comment, body: "Body")
      end

      let!(:syncer) do
        pr_service =
          MockGithubPRService.new(
            pull_request_data: {
              pr => pr_data,
            },
            pull_request_events: {
              pr => [[event_info, issue_comment]],
            },
          )

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates posts for issue comments" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(2)
      end

      it "puts the issue comment body in the created post" do
        syncer.sync_pull_request("owner/name", 101)

        expect(last_post_of_last_topic.raw).to include(issue_comment.body)
      end

      it "creates posts for issue comments idempotently" do
        syncer.sync_pull_request("owner/name", 101)

        expect { syncer.sync_pull_request("owner/name", 101) }.not_to change { Post.count }
      end
    end

    context "when the events contain a merged event" do
      let!(:merged_event) { DiscourseCodeReview::PullRequestEvent.create(:merged) }

      let!(:syncer) do
        pr_service =
          MockGithubPRService.new(
            pull_request_data: {
              pr => pr_data,
            },
            pull_request_events: {
              pr => [[event_info, merged_event]],
            },
          )

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates merged posts" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(2)
      end

      it "creates a small action" do
        syncer.sync_pull_request("owner/name", 101)

        expect(last_post_of_last_topic.action_code).to eq("merged")
      end
    end

    context "when the events contain a review thread started event" do
      let!(:review_thread) do
        DiscourseCodeReview::CommentThread.new(github_id: "github review thread id")
      end

      context "when the context is nil" do
        let!(:review_thread_started_event) do
          DiscourseCodeReview::PullRequestEvent.create(
            :review_thread_started,
            body: "Body",
            context: nil,
            thread: review_thread,
          )
        end

        let!(:syncer) do
          pr_service =
            MockGithubPRService.new(
              pull_request_data: {
                pr => pr_data,
              },
              pull_request_events: {
                pr => [[event_info, review_thread_started_event]],
              },
            )

          create_pr_syncer(pr_service, empty_user_querier)
        end

        it "creates review thread started posts" do
          expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(2)

          expect(last_post_of_last_topic.raw).to(include(review_thread_started_event.body))
        end
      end

      context "when the context is present" do
        let!(:context) do
          DiscourseCodeReview::CommentContext.new(path: "path/to/changed", diff_hunk: "some diff")
        end

        let!(:review_thread_started_event) do
          DiscourseCodeReview::PullRequestEvent.create(
            :review_thread_started,
            body: "Body",
            context: context,
            thread: review_thread,
          )
        end

        let!(:syncer) do
          pr_service =
            MockGithubPRService.new(
              pull_request_data: {
                pr => pr_data,
              },
              pull_request_events: {
                pr => [[event_info, review_thread_started_event]],
              },
            )

          create_pr_syncer(pr_service, empty_user_querier)
        end

        it "creates review thread started posts" do
          expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(2)

          expect(last_post_of_last_topic.raw).to(include(review_thread_started_event.body))
        end
      end
    end

    context "when the events contain a review thread comment" do
      let!(:review_thread) do
        DiscourseCodeReview::CommentThread.new(github_id: "github review thread id")
      end

      let!(:review_thread_started_event) do
        DiscourseCodeReview::PullRequestEvent.create(
          :review_thread_started,
          body: "Body",
          context: nil,
          thread: review_thread,
        )
      end

      let!(:review_comment) do
        DiscourseCodeReview::PullRequestEvent.create(
          :review_comment,
          body: "Reply Body",
          reply_to_github_id: event_info.github_id,
          thread: review_thread,
        )
      end

      let!(:syncer) do
        pr_service =
          MockGithubPRService.new(
            pull_request_data: {
              pr => pr_data,
            },
            pull_request_events: {
              pr => [[event_info, review_thread_started_event], [event_info2, review_comment]],
            },
          )

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates review comment posts" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(3)

        expect(last_post_of_last_topic.raw).to include(review_comment.body)
      end
    end

    context "when the events contain a renamed event" do
      let!(:renamed_event) do
        DiscourseCodeReview::PullRequestEvent.create(
          :renamed_title,
          previous_title: "Old Title",
          new_title: "New Title",
        )
      end

      let!(:syncer) do
        pr_service =
          MockGithubPRService.new(
            pull_request_data: {
              pr => pr_data,
            },
            pull_request_events: {
              pr => [[event_info, renamed_event]],
            },
          )

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates renamed title posts" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(2)
      end

      it "changes the title" do
        syncer.sync_pull_request("owner/name", 101)

        expect(last_topic.title).to eq("New Title (PR #101)")
      end
    end

    context "when the events contain a re-opened event" do
      let!(:closed_event) { DiscourseCodeReview::PullRequestEvent.create(:closed) }

      let!(:reopened_event) { DiscourseCodeReview::PullRequestEvent.create(:reopened) }

      let!(:syncer) do
        pr_service =
          MockGithubPRService.new(
            pull_request_data: {
              pr => pr_data,
            },
            pull_request_events: {
              pr => [[event_info, closed_event], [event_info2, reopened_event]],
            },
          )

        create_pr_syncer(pr_service, empty_user_querier)
      end

      it "creates re-opened posts" do
        expect { syncer.sync_pull_request("owner/name", 101) }.to change { Post.count }.by(3)
      end

      it "leaves the topic open" do
        syncer.sync_pull_request("owner/name", 101)

        expect(last_topic).to_not be_closed
      end
    end
  end

  describe "#mirror_pr_post" do
    let!(:pr_service) { mock }
    let!(:user_querier) { mock }
    let!(:syncer) { create_pr_syncer(pr_service, user_querier) }
    fab!(:topic) do
      Fabricate(:topic, category: category).tap do |topic|
        topic.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_ISSUE_NUMBER] = "102"
        topic.save_custom_fields
      end
    end

    fab!(:first_post) { Fabricate(:post, topic: topic) }

    context "when a whisper is provided" do
      fab!(:post) { Fabricate(:post, topic: topic, post_type: Post.types[:whisper]) }

      it "does not send the post to github" do
        pr_service.expects(:create_issue_comment).never
        syncer.mirror_pr_post(post)
      end
    end

    context "when a small action is provided" do
      fab!(:post) { Fabricate(:post, topic: topic, post_type: Post.types[:small_action]) }

      it "does not send the post to github" do
        pr_service.expects(:create_issue_comment).never
        syncer.mirror_pr_post(post)
      end
    end

    context "when a regular post is provided" do
      fab!(:post) { Fabricate(:post, topic: topic) }

      it "sends the post to github" do
        pr_service
          .expects(:create_issue_comment)
          .with("owner/name", 102, is_a(String))
          .returns(node_id: "important node")

        syncer.mirror_pr_post(post)

        expect(post.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID]).to eq(
          "important node",
        )
      end
    end

    context "when a reply is provided" do
      fab!(:post) { Fabricate(:post, topic: topic, reply_to_post_number: 1) }
      before_all do
        first_post.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_THREAD_ID] = "thread 1"
        first_post.save_custom_fields
      end

      it "sends the post to github" do
        pr_service
          .expects(:create_review_comment)
          .with("owner/name", 102, is_a(String), "thread 1")
          .returns(node_id: "important node")

        syncer.mirror_pr_post(post)

        expect(post.custom_fields[DiscourseCodeReview::GithubPRSyncer::GITHUB_NODE_ID]).to eq(
          "important node",
        )
      end
    end
  end
end
