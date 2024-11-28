import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import topicFixtures from "discourse/tests/fixtures/topic";
import {
  acceptance,
  exists,
  updateCurrentUser,
} from "discourse/tests/helpers/qunit-helpers";
import { cloneJSON } from "discourse-common/lib/object";

acceptance("review desktop", function (needs) {
  needs.user({
    can_review_code: true,
  });
  needs.settings({
    code_review_approved_tag: "approved",
    code_review_pending_tag: "pending",
    code_review_followup_tag: "followup",
  });
  needs.pretender((server) => {
    const json = cloneJSON(topicFixtures["/t/280/1.json"]);
    json.tags = ["pending"];

    server.get("/t/281.json", () => {
      return [200, { "Content-Type": "application/json" }, json];
    });
  });

  test("shows approve button by default", async (assert) => {
    await visit("/t/internationalization-localization/281");

    assert.ok(exists("#topic-footer-button-approve"));
  });

  test("hides approve button if user is self", async (assert) => {
    updateCurrentUser({ id: 1 });

    await visit("/t/this-is-a-test-topic/9/1");

    assert.notOk(exists("#topic-footer-button-approve"));
  });
});
