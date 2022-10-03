# frozen_string_literal: true

require 'rails_helper'

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
  let!(:pr) {
    DiscourseCodeReview::PullRequest.new(
      owner: "owner",
      name: "name",
      issue_number: 101,
    )
  }

  let!(:actor) {
    DiscourseCodeReview::Actor.new(
      github_login: "coder1234",
    )
  }

  let!(:issue_comment1) {
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "some github id",
        created_at: Time.parse("2000-01-01 00:00:00 UTC"),
        actor: actor
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :issue_comment,
        body: "some legitimate comment"
      )

    [event_info, event]
  }

  let!(:issue_comment2) {
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "some github id",
        created_at: Time.parse("2000-01-01 01:00:00 UTC"),
        actor: actor
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :issue_comment,
        body: "another legitimate comment"
      )

    [event_info, event]
  }

  let!(:commit_thread) {
    DiscourseCodeReview::CommitThread.new(
      github_id: "commit thread github id",
      actor: actor,
      created_at: Time.parse("2000-01-01 02:00:00 UTC"),
      commit_sha: "deadbeef"
    )
  }

  let!(:commit_thread_event) {
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "commit thread github id",
        created_at: Time.parse("2000-01-01 02:00:00 UTC"),
        actor: actor
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :commit_thread_started,
        commit_sha: "deadbeef"
      )

    [event_info, event]
  }

  let!(:review_thread) {
    DiscourseCodeReview::CommentThread.new(
      github_id: "review thread github id",
    )
  }

  let!(:first_review_thread_comment) {
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "first review thread comment github id",
        created_at: Time.parse("2000-01-01 03:00:00 UTC"),
        actor: actor
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :review_thread_started,
        body: "yet another totally legitimate comment",
        context: nil,
        thread: review_thread
      )

    [event_info, event]
  }

  let!(:second_review_thread_comment) {
    event_info =
      DiscourseCodeReview::PullRequestEventInfo.new(
        github_id: "second review thread comment github id",
        created_at: Time.parse("2000-01-01 04:00:00 UTC"),
        actor: actor
      )

    event =
      DiscourseCodeReview::PullRequestEvent.create(
        :review_comment,
        body: "and now for something completely different",
        reply_to_github_id: first_review_thread_comment[0].github_id,
        thread: review_thread
      )

    [event_info, event]
  }

  describe "#pull_request_events" do
    it "preserves timeline events" do
      pr_querier =
        MockPRQuerier.new(
          timeline: {
            pr => [issue_comment1]
          }
        )

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([issue_comment1])
    end

    it "preserves timeline event order" do
      pr_querier =
        MockPRQuerier.new(
          timeline: {
            pr => [
              issue_comment1,
              issue_comment2
            ]
          }
        )

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([issue_comment1, issue_comment2])
    end

    it "turns commit threads into events" do
      pr_querier =
        MockPRQuerier.new(
          commit_threads: {
            pr => [commit_thread]
          }
        )

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([commit_thread_event])
    end

    it "de-duplicates commit threads" do
      pr_querier =
        MockPRQuerier.new(
          commit_threads: {
            pr => [
              commit_thread,
              commit_thread
            ]
          }
        )

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
            pr => [review_thread]
          },
          first_review_thread_comment: {
            review_thread => first_review_thread_comment
          }
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
            pr => [review_thread]
          },
          first_review_thread_comment: {
            review_thread => first_review_thread_comment
          },
          subsequent_review_thread_comments: {
            review_thread => [second_review_thread_comment]
          }
        )

      result =
        DiscourseCodeReview::Source::GithubPRService
          .new(nil, pr_querier)
          .pull_request_events(pr)
          .to_a

      expect(result).to eq([first_review_thread_comment, second_review_thread_comment])
    end
  end
end
