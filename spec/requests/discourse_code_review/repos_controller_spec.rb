# frozen_string_literal: true

require "rails_helper"

describe DiscourseCodeReview::ReposController do
  before { SiteSetting.code_review_github_webhook_secret = "github webhook secret" }

  def set_client(client)
    DiscourseCodeReview.stubs(:octokit_bot_client).returns(client)
  end

  let!(:webhook_config) do
    {
      url: "https://#{Discourse.current_hostname}/code-review/webhook",
      content_type: "json",
      secret: SiteSetting.code_review_github_webhook_secret,
    }
  end

  let!(:webhook_events) do
    %w[
      commit_comment
      issue_comment
      pull_request
      pull_request_review
      pull_request_review_comment
      push
    ]
  end

  context "when user is not signed in" do
    it "is inaccessible" do
      get "/admin/plugins/code-review"

      expect(response.status).to eq(404)
    end
  end

  context "when user is not staff" do
    before { sign_in Fabricate(:user) }

    it "is inaccessible" do
      get "/admin/plugins/code-review"

      expect(response.status).to eq(404)
    end
  end

  context "when user is admin" do
    fab!(:admin) { Fabricate(:admin) }

    before { sign_in(admin) }

    it "is accessible" do
      get "/admin/plugins/code-review"

      expect(response.status).to eq(200)
    end

    describe "#index" do
      context "when the plugin is not configured" do
        before do
          SiteSetting.code_review_github_token = ""
          SiteSetting.code_review_github_webhook_secret = ""
        end

        it "returns a friendly error to the client" do
          get "/admin/plugins/code-review/organizations/org/repos.json"
          expect(response.parsed_body).to eq(
            "error" => I18n.t("discourse_code_review.bad_github_credentials_error"),
            "failed" => "FAILED",
          )
        end
      end

      context "when the API returns Octokit::Unauthorized" do
        let!(:client) do
          client = mock
          client.stubs(:organization_repositories).with("org").raises(Octokit::Unauthorized)
          client
        end

        before { set_client(client) }

        it "returns a friendly error to the client" do
          get "/admin/plugins/code-review/organizations/org/repos.json"
          expect(JSON.parse(response.body)).to eq(
            "error" => I18n.t("discourse_code_review.bad_github_credentials_error"),
            "failed" => "FAILED",
          )
        end
      end
    end

    describe "#has_configured_webhook" do
      context "when the API returns Octokit::NotFound" do
        let!(:client) do
          client = mock
          client.stubs(:hooks).with("org/repo").raises(Octokit::NotFound)
          client
        end

        before { set_client(client) }

        it "returns a friendly error to the client" do
          get "/admin/plugins/code-review/organizations/org/repos/repo/has-configured-webhook.json"
          expect(JSON.parse(response.body)).to eq(
            "error" => I18n.t("discourse_code_review.bad_github_permissions_error"),
            "failed" => "FAILED",
          )
        end
      end

      context "when a webhook is configured" do
        let(:repo_name) { "repo" }
        let!(:client) do
          client = mock
          client
            .stubs(:hooks)
            .with("org/#{repo_name}")
            .returns(
              [
                {
                  events: webhook_events,
                  config: {
                    content_type: "json",
                    url: "https://#{Discourse.current_hostname}/code-review/webhook",
                  },
                  id: 101,
                },
              ],
            )
          client
        end

        before { set_client(client) }

        it "says yes" do
          get "/admin/plugins/code-review/organizations/org/repos/#{repo_name}/has-configured-webhook.json"
          expect(JSON.parse(response.body)).to eq("has_configured_webhook" => true)
        end

        context "when repo name has a . in it" do
          let(:repo_name) { "Some-coolrepo.org" }

          it "returns the right response" do
            get "/admin/plugins/code-review/organizations/org/repos/#{repo_name}/has-configured-webhook.json"
            expect(response.status).to eq(200)
            expect(JSON.parse(response.body)).to eq("has_configured_webhook" => true)
          end
        end
      end

      context "when no webhook is configured" do
        let!(:client) do
          client = mock
          client.stubs(:hooks).with("org/repo").returns([])
          client
        end

        before { set_client(client) }

        it "says no" do
          get "/admin/plugins/code-review/organizations/org/repos/repo/has-configured-webhook.json"
          expect(JSON.parse(response.body)).to eq("has_configured_webhook" => false)
        end
      end

      context "when a webhook is configured, but has different events" do
        let!(:client) do
          client = mock
          client
            .stubs(:hooks)
            .with("org/repo")
            .returns(
              [
                {
                  events: webhook_events + ["other_event"],
                  config: {
                    content_type: "json",
                    url: "https://#{Discourse.current_hostname}/code-review/webhook",
                  },
                  id: 101,
                },
              ],
            )
          client
        end

        before { set_client(client) }

        it "says no" do
          get "/admin/plugins/code-review/organizations/org/repos/repo/has-configured-webhook.json"
          expect(JSON.parse(response.body)).to eq("has_configured_webhook" => false)
        end
      end

      context "when a webhook is configured, but has different content_type" do
        let!(:client) do
          client = mock
          client
            .stubs(:hooks)
            .with("org/repo")
            .returns(
              [
                {
                  events: webhook_events,
                  config: {
                    content_type: "jsonish",
                    url: "https://#{Discourse.current_hostname}/code-review/webhook",
                  },
                  id: 101,
                },
              ],
            )
          client
        end

        before { set_client(client) }

        it "says no" do
          get "/admin/plugins/code-review/organizations/org/repos/repo/has-configured-webhook.json"
          expect(JSON.parse(response.body)).to eq("has_configured_webhook" => false)
        end
      end

      context "when a webhook is configured, but has different url" do
        let!(:client) do
          client = mock
          client
            .stubs(:hooks)
            .with("org/repo")
            .returns(
              [
                {
                  events: webhook_events,
                  config: {
                    content_type: "json",
                    url: "https://example.com/some-webhook",
                  },
                  id: 101,
                },
              ],
            )
          client
        end

        before { set_client(client) }

        it "says no" do
          get "/admin/plugins/code-review/organizations/org/repos/repo/has-configured-webhook.json"
          expect(JSON.parse(response.body)).to eq("has_configured_webhook" => false)
        end
      end
    end

    describe "#configure_webhook" do
      context "when no existing webhook hits the right url" do
        let!(:client) do
          client = mock
          client
            .stubs(:hooks)
            .with("org/repo")
            .returns(
              [
                { config: { url: "https://not-your-hostname.com/code-review/webhook" } },
                { config: { url: "https://#{Discourse.current_hostname}/wrong-path" } },
              ],
            )
          client.expects(:create_hook).with(
            "org/repo",
            "web",
            webhook_config,
            events: webhook_events,
            active: true,
          )
          client
        end

        before { set_client(client) }

        it "creates a new webhook" do
          post "/admin/plugins/code-review/organizations/org/repos/repo/configure-webhook.json"
          expect(JSON.parse(response.body)).to eq("has_configured_webhook" => true)
        end
      end

      context "when a pre-existing webhook hits the right url" do
        let!(:client) do
          client = mock
          client
            .stubs(:hooks)
            .with("org/repo")
            .returns(
              [
                {
                  config: {
                    url: "https://#{Discourse.current_hostname}/code-review/webhook",
                  },
                  id: 101,
                },
              ],
            )
          client.expects(:edit_hook).with(
            "org/repo",
            101,
            "web",
            webhook_config,
            events: webhook_events,
            active: true,
          )
          client
        end

        before { set_client(client) }

        it "edits the webhook " do
          post "/admin/plugins/code-review/organizations/org/repos/repo/configure-webhook.json"
          expect(JSON.parse(response.body)).to eq("has_configured_webhook" => true)
        end
      end
    end
  end
end
