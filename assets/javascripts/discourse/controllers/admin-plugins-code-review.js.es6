import { ajax } from "discourse/lib/ajax";

const prefix = "/admin/plugins/code-review";

export default Ember.Controller.extend({
  init() {
    this._super(...arguments);

    const organizations = Ember.A([]);
    this.set("organizations", organizations);

    ajax(`${prefix}/organizations.json`).then((orgNames) => {
      for (const orgName of orgNames) {
        let organization = Ember.Object.create({
          name: orgName,
          repos: Ember.A([]),
        });
        organizations.pushObject(organization);

        ajax(`${prefix}/organizations/${orgName}/repos.json`).then(
          (repoNames) => {
            for (const repoName of repoNames) {
              let repo = Ember.Object.create({
                name: repoName,
                hasConfiguredWebhook: null,
                receivedWebhookState: false,
              });
              organization.repos.pushObject(repo);

              ajax(
                `${prefix}/organizations/${orgName}/repos/${repoName}/has-configured-webhook.json`
              ).then((response) => {
                repo.set("receivedWebhookState", true);
                repo.set(
                  "hasConfiguredWebhook",
                  response["has_configured_webhook"]
                );
              });
            }
          }
        );
      }
    });
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
