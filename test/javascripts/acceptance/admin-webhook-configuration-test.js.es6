import {
  acceptance,
  count,
  exists,
  query,
} from "discourse/tests/helpers/qunit-helpers";
import { click, visit } from "@ember/test-helpers";
import { test } from "qunit";

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

    assert.equal(organizations.length, 2);
    const [org1, org2] = organizations;

    assert.equal(org1.querySelector("h2").innerText, "org1");
    assert.equal(org2.querySelector("h2").innerText, "org2");

    const org1Repos = org1.querySelectorAll(".code-review-webhook-repo");
    const org2Repos = org2.querySelectorAll(".code-review-webhook-repo");

    assert.equal(org1Repos.length, 1);
    assert.equal(org2Repos.length, 2);

    const repo1 = org1Repos[0];
    const [repo2, repo3] = org2Repos;

    assert.equal(repo1.querySelector("h3").innerText, "repo1");
    assert.equal(repo2.querySelector("h3").innerText, "repo2");
    assert.equal(repo3.querySelector("h3").innerText, "repo3");

    assert.equal(
      repo1.querySelectorAll(".code-review-webhook-not-configured").length,
      1
    );
    assert.equal(
      repo2.querySelectorAll(".code-review-webhook-configured").length,
      1
    );
    assert.equal(
      repo3.querySelectorAll(".code-review-webhook-not-configured").length,
      1
    );
  });

  test("Should send requests to change each unconfigured webhook", async (assert) => {
    await visit("/admin/plugins/code-review");
    await click(".code-review-configure-webhooks-button");

    assert.equal(count(".code-review-webhook-configured"), 3);
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
    assert.equal(query(".modal-body").innerText, "credential error");
    await click(".modal-footer .btn-primary");
    assert.ok(exists(".code-review-configure-webhooks-button:disabled"));
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
      assert.equal(query(".modal-body").innerText, "permissions error");
      await click(".modal-footer .btn-primary");
      assert.ok(exists(".code-review-configure-webhooks-button:disabled"));
    });
  }
);
