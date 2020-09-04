import selectKit from "helpers/select-kit-helper";
import { updateCurrentUser, acceptance } from "helpers/qunit-helpers";
import Fixtures from "fixtures/topic";

acceptance("review mobile", {
  loggedIn: true,
  mobileView: true,
  settings: {
    code_review_approved_tag: "approved",
    code_review_pending_tag: "pending",
    code_review_followup_tag: "followup",
  },
});

QUnit.test("shows approve button by default", async (assert) => {
  const json = Object.assign({}, Fixtures["/t/280/1.json"]);

  json.tags = ["pending"];

  /* global server */
  server.get("/t/281.json", () => {
    return [200, { "Content-Type": "application/json" }, json];
  });

  await visit("/t/internationalization-localization/281");

  const menu = selectKit(".topic-footer-mobile-dropdown");
  await menu.expand();

  assert.ok(menu.rowByValue("approve").exists());
});

QUnit.test("hides approve button if user is self", async (assert) => {
  updateCurrentUser({ id: 1 });

  await visit("/t/this-is-a-test-topic/9/1");

  const menu = selectKit(".topic-footer-mobile-dropdown");
  await menu.expand();

  assert.notOk(menu.rowByValue("approve").exists());
});
