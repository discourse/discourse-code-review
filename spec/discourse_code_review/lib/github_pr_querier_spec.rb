# frozen_string_literal: true

require "rails_helper"
require_relative "../../helpers/integration"

describe DiscourseCodeReview::Source::GithubPRQuerier, type: :code_review_integration do
  let(:pr_querier) do
    DiscourseCodeReview::Source::GithubPRQuerier.new(DiscourseCodeReview.graphql_client)
  end

  let(:pr) { DiscourseCodeReview::PullRequest.new(owner: "owner", name: "name", issue_number: 100) }

  describe "#associated_pull_requests" do
    it "does not error out when the query finds nothing" do
      GraphQLClientMock.any_instance.expects(:execute).returns({})

      expect(pr_querier.associated_pull_requests(anything, anything, anything).to_a).to be_empty
    end
  end

  describe "#timeline" do
    let(:raw_events) do
      [
        {
          __typename: "PullRequestReview",
          id: "PRR_kwDOCTCBxM5NoRuj",
          createdAt: "2023-02-16T22:53:41Z",
          actor: {
            login: "s3lase",
          },
          body: "General review comment",
        },
        {
          __typename: "IssueComment",
          id: "IC_kwDOCTCBxM5kaSjN",
          createdAt: "2023-08-19T00:47:19Z",
          actor: {
            login: "s3lase",
          },
          body: "And here too",
        },
      ]
    end

    let(:raw_events_without_body) do
      [
        {
          __typename: "PullRequestReview",
          id: "PRR_kwDOCTCBxM5NoTQO",
          createdAt: "2023-02-16T23:00:49Z",
          actor: {
            login: "s3lase",
          },
          body: "",
        },
      ]
    end

    it "returns all events" do
      DiscourseCodeReview::Source::GithubPRQuerier
        .any_instance
        .expects(:timeline_events_for)
        .returns(raw_events)

      timeline = pr_querier.timeline(pr).to_a
      first_event, second_event = timeline

      expect(timeline.length).to eq(2)

      expect(first_event[0]).to be_a(DiscourseCodeReview::PullRequestEventInfo)
      expect(first_event[0].github_id).to eq("PRR_kwDOCTCBxM5NoRuj")
      expect(first_event[1]).to be_a(DiscourseCodeReview::PullRequestEvent::IssueComment)
      expect(first_event[1].body).to eq("General review comment")

      expect(second_event[0]).to be_a(DiscourseCodeReview::PullRequestEventInfo)
      expect(second_event[0].github_id).to eq("IC_kwDOCTCBxM5kaSjN")
      expect(second_event[1]).to be_a(DiscourseCodeReview::PullRequestEvent::IssueComment)
      expect(second_event[1].body).to eq("And here too")
    end

    it "skips PullRequestReview events without body" do
      DiscourseCodeReview::Source::GithubPRQuerier
        .any_instance
        .expects(:timeline_events_for)
        .returns(raw_events + raw_events_without_body)

      timeline = pr_querier.timeline(pr).to_a

      expect(timeline.length).to eq(2)
      expect(timeline.map(&:first).map(&:github_id)).not_to include(
        raw_events_without_body.map { |e| e[:id] },
      )
    end
  end
end
