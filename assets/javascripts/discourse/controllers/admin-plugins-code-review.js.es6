import { ajax } from "discourse/lib/ajax";
import I18n from "I18n";
import discourseComputed from "discourse-common/utils/decorators";
import { popupAjaxError } from "discourse/lib/ajax-error";

const prefix = "/admin/plugins/code-review";

export default Ember.Controller.extend({
  init() {
    this._super(...arguments);

    const organizations = Ember.A([]);
    this.set("organizations", organizations);
    this.set("loading", true);

    ajax(`${prefix}/organizations.json`).then((orgNames) => {
      let promises = [];
      for (const orgName of orgNames) {
        let organization = Ember.Object.create({
          name: orgName,
          repos: Ember.A([]),
        });
        organizations.pushObject(organization);
        promises.push(this.loadOrganizationRepos(organization));
      }

      Promise.all(promises)
        .then(() => this.set("loading", false))
        .catch((err) => {
          this.set("organizationReposLoadFailed", true);
        });
    });
  },

  loadOrganizationRepos(organization) {
    return ajax(`${prefix}/organizations/${organization.name}/repos.json`)
      .then((repoNames) => {
        for (const repoName of repoNames) {
          let repo = Ember.Object.create({
            name: repoName,
            hasConfiguredWebhook: null,
            receivedWebhookState: false,
          });
          organization.repos.pushObject(repo);
        }

        // No point continuing doing requests for the webhooks if there
        // is an error with the first request, the token permissions must be fixed first;
        this.hasConfiguredWebhook(organization.name, organization.repos[0])
          .then(() => {
            Promise.all(
              this.loadWebhookConfiguration(
                organization.name,
                organization.repos
              )
            ).then(() => this.set("loading", false));
          })
          .catch((response) => {
            this.setProperties({ loading: false, loadError: true });
            popupAjaxError(response);
          });
      })
      .catch((response) => {
        this.setProperties({ loading: false, loadError: true });
        popupAjaxError(response);
      });
  },

  loadWebhookConfiguration(orgName, repos) {
    let promises = [];
    for (let repo of repos) {
      promises.push(this.hasConfiguredWebhook(orgName, repo));
    }
    return promises;
  },

  hasConfiguredWebhook(orgName, repo) {
    if (repo.receivedWebhookState) {
      return Promise.resolve(true);
    }

    return ajax(
      `${prefix}/organizations/${orgName}/repos/${repo.name}/has-configured-webhook.json`
    )
      .then((response) => {
        repo.set("receivedWebhookState", true);
        repo.set("hasConfiguredWebhook", response["has_configured_webhook"]);
      })
      .catch(popupAjaxError);
  },

  @discourseComputed("loadError")
  configureWebhooksTitle(loadError) {
    if (!loadError) {
      return "";
    }

    return "code_review.webhooks_load_error";
  },

  actions: {
    configureWebhook(organization, repo) {
      if (repo.hasConfiguredWebhook === false) {
        ajax(
          `${prefix}/organizations/${organization.name}/repos/${repo.name}/configure-webhook.json`,
          {
            type: "POST",
          }
        ).then((response) => {
          repo.set("hasConfiguredWebhook", response["has_configured_webhook"]);
        });
      }
    },

    configureWebhooks() {
      for (const organization of this.organizations) {
        for (const repo of organization.repos) {
          if (repo.hasConfiguredWebhook === false) {
            ajax(
              `${prefix}/organizations/${organization.name}/repos/${repo.name}/configure-webhook.json`,
              {
                type: "POST",
              }
            ).then((response) => {
              repo.set(
                "hasConfiguredWebhook",
                response["has_configured_webhook"]
              );
            });
          }
        }
      }
    },
  },
});
