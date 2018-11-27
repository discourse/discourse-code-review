import { replaceCurrentUser, acceptance } from "helpers/qunit-helpers";
import { clearCallbacks } from "select-kit/mixins/plugin-api";

acceptance("review mobile", {
  loggedIn: true,
  mobileView: true,
  afterEach() {
    clearCallbacks();
  },
  beforeEach() {
    // we need to clean this up in core
    // plugin api keeps being re-initialized
    clearCallbacks();
  }
});

QUnit.test("shows approve button by default", async assert => {
  await visit("/t/internationalization-localization/280");

  const menu = selectKit(".topic-footer-mobile-dropdown");
  await menu.expand();

  assert.ok(menu.rowByValue("approve").exists());
});

QUnit.test("hides approve button if user is self", async assert => {
  replaceCurrentUser({ id: 1 });

  await visit("/t/this-is-a-test-topic/9/1");

  const menu = selectKit(".topic-footer-mobile-dropdown");
  await menu.expand();

  assert.ok(!menu.rowByValue("approve").exists());
});
