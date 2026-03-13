import { click, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance, query } from "discourse/tests/helpers/qunit-helpers";

const restPrefix = "/admin/plugins/code-review";

acceptance("Github Webhook Configuration", function (needs) {
  needs.user();

  needs.pretender((server, helper) => {
    server.get(`${restPrefix}/organizations.json`, () => {
      return helper.response(["org1", "org2"]);
    });

    server.get(`${restPrefix}/organizations/org1/repos.json`, () => {
      return helper.response(["repo1"]);
    });

    server.get(`${restPrefix}/organizations/org2/repos.json`, () => {
      return helper.response(["repo2", "repo3"]);
    });

    server.get(
      `${restPrefix}/organizations/org1/repos/repo1/has-configured-webhook.json`,
      () => {
        return helper.response({
          has_configured_webhook: false,
        });
      }
    );

    server.get(
      `${restPrefix}/organizations/org2/repos/repo2/has-configured-webhook.json`,
      () => {
        return helper.response({
          has_configured_webhook: true,
        });
      }
    );

    server.get(
      `${restPrefix}/organizations/org2/repos/repo3/has-configured-webhook.json`,
      () => {
        return helper.response({
          has_configured_webhook: false,
        });
      }
    );

    server.post(
      `${restPrefix}/organizations/org1/repos/repo1/configure-webhook.json`,
      () => {
        return helper.response({
          has_configured_webhook: true,
        });
      }
    );

    server.post(
      `${restPrefix}/organizations/org2/repos/repo3/configure-webhook.json`,
      () => {
        return helper.response({
          has_configured_webhook: true,
        });
      }
    );
  });

  test("Should display correctly", async (assert) => {
    await visit("/admin/plugins/code-review");

    const tree = query(".code-review-webhook-tree");
    const organizations = tree.querySelectorAll(".code-review-webhook-org");

    assert.strictEqual(organizations.length, 2);
    const [org1, org2] = organizations;

    assert.dom("h2", org1).hasText("org1");
    assert.dom("h2", org2).hasText("org2");

    const org1Repos = org1.querySelectorAll(".code-review-webhook-repo");
    const org2Repos = org2.querySelectorAll(".code-review-webhook-repo");

    assert.strictEqual(org1Repos.length, 1);
    assert.strictEqual(org2Repos.length, 2);

    const repo1 = org1Repos[0];
    const [repo2, repo3] = org2Repos;

    assert.dom("h3", repo1).hasText("repo1");
    assert.dom("h3", repo2).hasText("repo2");
    assert.dom("h3", repo3).hasText("repo3");

    assert
      .dom(".code-review-webhook-not-configured", repo1)
      .exists({ count: 1 });
    assert.dom(".code-review-webhook-configured", repo2).exists({ count: 1 });
    assert
      .dom(".code-review-webhook-not-configured", repo3)
      .exists({ count: 1 });
  });

  test("Should send requests to change each unconfigured webhook", async (assert) => {
    await visit("/admin/plugins/code-review");
    await click(".code-review-configure-webhooks-button");

    assert.dom(".code-review-webhook-configured").exists({ count: 3 });
  });
});

acceptance("GitHub Webhook Configuration - Repo List Error", function (needs) {
  needs.user();

  needs.pretender((server, helper) => {
    server.get(`${restPrefix}/organizations.json`, () => {
      return helper.response(["org1"]);
    });

    server.get(`${restPrefix}/organizations/org1/repos.json`, () => {
      return helper.response(401, {
        error: "credential error",
        failed: "FAILED",
      });
    });
  });

  test("Should show an error message", async (assert) => {
    await visit("/admin/plugins/code-review");
    assert.dom(".dialog-body").hasText("credential error");

    await click(".dialog-footer .btn-primary");
    assert.dom(".code-review-configure-webhooks-button:disabled").exists();
  });
});

acceptance(
  "GitHub Webhook Configuration - Webhook Config Get Error",
  function (needs) {
    needs.user();

    needs.pretender((server, helper) => {
      server.get(`${restPrefix}/organizations.json`, () => {
        return helper.response(["org1"]);
      });

      server.get(`${restPrefix}/organizations/org1/repos.json`, () => {
        return helper.response(["repo1"]);
      });

      server.get(
        `${restPrefix}/organizations/org1/repos/repo1/has-configured-webhook.json`,
        () => {
          return helper.response(400, {
            error: "permissions error",
            failed: "FAILED",
          });
        }
      );
    });

    test("Should show an error message", async (assert) => {
      await visit("/admin/plugins/code-review");
      assert.dom(".dialog-body").hasText("permissions error");

      await click(".dialog-footer .btn-primary");
      assert.dom(".code-review-configure-webhooks-button:disabled").exists();
    });
  }
);
