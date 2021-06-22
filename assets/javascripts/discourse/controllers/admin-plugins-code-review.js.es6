import { ajax } from "discourse/lib/ajax";
import { Promise } from "rsvp";
import discourseComputed from "discourse-common/utils/decorators";
import { popupAjaxError } from "discourse/lib/ajax-error";
import Controller from "@ember/controller";
import EmberObject from "@ember/object";
import { A } from "@ember/array";

const prefix = "/admin/plugins/code-review";

export default Controller.extend({
  organizations: null,
  loading: true,

  async loadOrganizations() {
    try {
      let orgNames = await ajax(`${prefix}/organizations.json`);
      this.set("organizations", A([]));

      for (const orgName of orgNames) {
        let organization = EmberObject.create({
          name: orgName,
          repos: A([]),
        });
        this.organizations.pushObject(organization);
      }

      await Promise.all(
        this.organizations.map(this.loadOrganizationRepos.bind(this))
      );
    } catch (error) {
      this.set("organizationReposLoadFailed", true);
    } finally {
      this.set("loading", false);
    }
  },

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
        organization.repos.pushObject(repo);
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
      this.set("loadError", true);
      popupAjaxError(response);
    } finally {
      this.set("loading", false);
    }
  },

  async hasConfiguredWebhook(orgName, repo) {
    if (repo.receivedWebhookState) {
      return true;
    }

    let response = await ajax(
      `${prefix}/organizations/${orgName}/repos/${repo.name}/has-configured-webhook.json`
    );

    repo.set("receivedWebhookState", true);
    repo.set("hasConfiguredWebhook", response["has_configured_webhook"]);
  },

  @discourseComputed("loadError")
  configureWebhooksTitle(loadError) {
    if (!loadError) {
      return "";
    }

    return "code_review.webhooks_load_error";
  },

  actions: {
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
    },

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

            repo.set(
              "hasConfiguredWebhook",
              response["has_configured_webhook"]
            );
          }
        }
      }
    },
  },
});
