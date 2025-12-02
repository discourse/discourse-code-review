import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import EmberObject, { action } from "@ember/object";
import { TrackedArray } from "@ember-compat/tracked-built-ins";
import { Promise } from "rsvp";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { trackedArray } from "discourse/lib/tracked-tools";

const prefix = "/admin/plugins/code-review";

export default class AdminPluginsCodeReviewController extends Controller {
  @tracked loadError = false;
  @tracked loading = true;
  @trackedArray organizations = null;

  async loadOrganizations() {
    try {
      let orgNames = await ajax(`${prefix}/organizations.json`);
      this.organizations = [];

      for (const orgName of orgNames) {
        let organization = EmberObject.create({
          name: orgName,
          repos: new TrackedArray(),
        });
        this.organizations.push(organization);
      }

      await Promise.all(
        this.organizations.map(this.loadOrganizationRepos.bind(this))
      );
    } catch {
      this.loadError = true;
    } finally {
      this.loading = false;
    }
  }

  async loadOrganizationRepos(organization) {
    try {
      let repoNames = await ajax(
        `${prefix}/organizations/${organization.name}/repos.json`
      );

      for (const repoName of repoNames) {
        let repo = EmberObject.create({
          name: repoName,
          hasConfiguredWebhook: null,
          receivedWebhookState: false,
        });
        organization.repos.push(repo);
      }

      // No point continuing doing requests for the webhooks if there
      // is an error with the first request, the token permissions must be fixed first
      await this.hasConfiguredWebhook(organization.name, organization.repos[0]);

      await Promise.all(
        organization.repos.map((repo) =>
          this.hasConfiguredWebhook(organization.name, repo)
        )
      );
    } catch (response) {
      this.loadError = true;
      popupAjaxError(response);
    } finally {
      this.loading = false;
    }
  }

  async hasConfiguredWebhook(orgName, repo) {
    if (repo.receivedWebhookState) {
      return true;
    }

    let response = await ajax(
      `${prefix}/organizations/${orgName}/repos/${repo.name}/has-configured-webhook.json`
    );

    repo.set("receivedWebhookState", true);
    repo.set("hasConfiguredWebhook", response["has_configured_webhook"]);
  }

  get configureWebhooksTitle() {
    if (!this.loadError) {
      return "";
    }

    return "code_review.webhooks_load_error";
  }

  @action
  async configureWebhook(organization, repo) {
    if (repo.hasConfiguredWebhook === false) {
      let response = await ajax(
        `${prefix}/organizations/${organization.name}/repos/${repo.name}/configure-webhook.json`,
        {
          type: "POST",
        }
      );

      repo.set("hasConfiguredWebhook", response["has_configured_webhook"]);
    }
  }

  @action
  async configureWebhooks() {
    for (const organization of this.organizations) {
      for (const repo of organization.repos) {
        if (repo.hasConfiguredWebhook === false) {
          let response = await ajax(
            `${prefix}/organizations/${organization.name}/repos/${repo.name}/configure-webhook.json`,
            {
              type: "POST",
            }
          );

          repo.set("hasConfiguredWebhook", response["has_configured_webhook"]);
        }
      }
    }
  }
}
