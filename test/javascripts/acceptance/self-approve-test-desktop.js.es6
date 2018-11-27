import { replaceCurrentUser, acceptance } from "helpers/qunit-helpers";

acceptance("review desktop", {
  loggedIn: true,
  mobileView: false
});

QUnit.test("shows approve button by default", async assert => {
  await visit("/t/internationalization-localization/280");

  assert.ok(count(".approve-commit-button") > 0);
});

QUnit.test("hides approve button if user is self", async assert => {
  replaceCurrentUser({ id: 1 });

  await visit("/t/this-is-a-test-topic/9/1");

  assert.ok(count(".approve-commit-button") === 0);
});
