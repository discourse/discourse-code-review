import { replaceCurrentUser, acceptance } from "helpers/qunit-helpers";
import Fixtures from "fixtures/topic";

acceptance("review desktop", {
  loggedIn: true,
  settings: {
    code_review_approved_tag: "approved",
    code_review_pending_tag: "pending",
    code_review_followup_tag: "followup"
  }
});

QUnit.test("shows approve button by default", async assert => {
  const json = $.extend(true, {}, Fixtures["/t/280/1.json"]);

  json.tags = ["pending"];

  server.get("/t/281.json", () => {
    return [200, { "Content-Type": "application/json" }, json];
  });

  await visit("/t/internationalization-localization/281");

  assert.ok(exists("#topic-footer-button-approve"));
});

QUnit.test("hides approve button if user is self", async assert => {
  replaceCurrentUser({ id: 1 });

  await visit("/t/this-is-a-test-topic/9/1");

  assert.ok(!exists("#topic-footer-button-approve"));
});
