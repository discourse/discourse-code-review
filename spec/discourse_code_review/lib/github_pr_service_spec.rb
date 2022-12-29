# frozen_string_literal: true

require "rails_helper"

class MockPRQuerier
  def initialize(**opts)
    @opts = opts
  end

  def first_review_thread_comment(review_thread)
    @opts.fetch(:first_review_thread_comment, {}).fetch(review_thread, [])
  end

  def subsequent_review_thread_comments(review_thread)
    @opts.fetch(:subsequent_review_thread_comments, {}).fetch(review_thread, [])
  end

  def review_threads(pr)
    @opts.fetch(:review_threads, {}).fetch(pr, [])
  end

  def commit_threads(pr)
    @opts.fetch(:commit_threads, {}).fetch(pr, [])
  end

  def timeline(pr)
    @opts.fetch(:timeline, {}).fetch(pr, [])
  end

  def pull_request_data(pr)
    @opts.fetch(:pull_request_data, {}).fetch(pr, [])
  end

  def pull_requests(owner, name)
    @opts.fetch(:pull_requests, {}).fetch([owner, name], [])
  end

  def associated_pull_requests(owner, name, commit_sha)
    @opts.fetch(:associated_pull_requests, {}).fetch([owner, name, commit_sha], [])
  end
end

describe DiscourseCodeReview::Source::GithubPRService do
  let!(:pr) do
    DiscourseCodeReview::PullRequest.new(owner: "owner", name: "name", issue_number: 101)
  end

  let!(:external_pr) do
    DiscourseCodeReview::PullRequest.new(owner: "acme", name: "name", issue_number: 102)
  end

  let!(:actor) { DiscourseCodeReview::Actor.new(github_login: "coder1234") }

  let!(:issue_comment1) do
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "some github id",
        created_at: Time.parse("2000-01-01 00:00:00 UTC"),
        actor: actor,
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(:issue_comment, body: "some legitimate comment")

    [event_info, event]
  end

  let!(:issue_comment2) do
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "some github id",
        created_at: Time.parse("2000-01-01 01:00:00 UTC"),
        actor: actor,
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :issue_comment,
        body: "another legitimate comment",
      )

    [event_info, event]
  end

  let!(:commit_thread) do
    DiscourseCodeReview::CommitThread.new(
      github_id: "commit thread github id",
      actor: actor,
      created_at: Time.parse("2000-01-01 02:00:00 UTC"),
      commit_sha: "deadbeef",
    )
  end

  let!(:commit_thread_event) do
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "commit thread github id",
        created_at: Time.parse("2000-01-01 02:00:00 UTC"),
        actor: actor,
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(:commit_thread_started, commit_sha: "deadbeef")

    [event_info, event]
  end

  let!(:review_thread) do
    DiscourseCodeReview::CommentThread.new(github_id: "review thread github id")
  end

  let!(:first_review_thread_comment) do
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "first review thread comment github id",
        created_at: Time.parse("2000-01-01 03:00:00 UTC"),
        actor: actor,
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :review_thread_started,
        body: "yet another totally legitimate comment",
        context: nil,
        thread: review_thread,
      )

    [event_info, event]
  end

  let!(:second_review_thread_comment) do
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "second review thread comment github id",
        created_at: Time.parse("2000-01-01 04:00:00 UTC"),
        actor: actor,
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :review_comment,
        body: "and now for something completely different",
        reply_to_github_id: first_review_thread_comment[0].github_id,
        thread: review_thread,
      )

    [event_info, event]
  end

  describe "#pull_request_events" do
    it "preserves timeline events" do
      pr_querier = MockPRQuerier.new(timeline: { pr => [issue_comment1] })

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([issue_comment1])
    end

    it "preserves timeline event order" do
      pr_querier = MockPRQuerier.new(timeline: { pr => [issue_comment1, issue_comment2] })

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([issue_comment1, issue_comment2])
    end

    it "turns commit threads into events" do
      pr_querier = MockPRQuerier.new(commit_threads: { pr => [commit_thread] })

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([commit_thread_event])
    end

    it "de-duplicates commit threads" do
      pr_querier = MockPRQuerier.new(commit_threads: { pr => [commit_thread, commit_thread] })

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([commit_thread_event])
    end

    it "turns the first review thread comment into an event" do
      pr_querier =
        MockPRQuerier.new(
          review_threads: {
            pr => [review_thread],
          },
          first_review_thread_comment: {
            review_thread => first_review_thread_comment,
          },
        )

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([first_review_thread_comment])
    end

    it "turns other review thread comments into events" do
      pr_querier =
        MockPRQuerier.new(
          review_threads: {
            pr => [review_thread],
          },
          first_review_thread_comment: {
            review_thread => first_review_thread_comment,
          },
          subsequent_review_thread_comments: {
            review_thread => [second_review_thread_comment],
          },
        )

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([first_review_thread_comment, second_review_thread_comment])
    end
  end

  describe "#associated_pull_requests" do
    context "when including external repos" do
      it "does not filter out any pull requests" do
        DiscourseCodeReview.stubs(:github_organizations).returns(["owner"])

        pr_querier =
          MockPRQuerier.new(
            associated_pull_requests: {
              %w[discourse discourse-code-review 2914603cc78157be832a57d49b182d89e7e5ed1a] => [
                pr,
                external_pr,
              ],
            },
          )

        result =
          DiscourseCodeReview::Source::GithubPRService
            .new(nil, pr_querier)
            .associated_pull_requests(
              "discourse/discourse-code-review",
              "2914603cc78157be832a57d49b182d89e7e5ed1a",
              include_external: true,
            )
            .to_a

        expect(result).to eq([pr, external_pr])
      end
    end

    context "when not including external repos" do
      it "filters out any external pull requests" do
        DiscourseCodeReview.stubs(:github_organizations).returns(["owner"])

        pr_querier =
          MockPRQuerier.new(
            associated_pull_requests: {
              %w[discourse discourse-code-review 2914603cc78157be832a57d49b182d89e7e5ed1a] => [
                pr,
                external_pr,
              ],
            },
          )

        result =
          DiscourseCodeReview::Source::GithubPRService
            .new(nil, pr_querier)
            .associated_pull_requests(
              "discourse/discourse-code-review",
              "2914603cc78157be832a57d49b182d89e7e5ed1a",
              include_external: false,
            )
            .to_a

        expect(result).to eq([pr])
      end
    end
  end
end
