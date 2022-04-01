import { acceptance, query } from "discourse/tests/helpers/qunit-helpers";
import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import I18n from "I18n";

acceptance("User Activity / Approval Given - empty state", function (needs) {
  const currentUser = "eviltrout";
  needs.user();

  needs.pretender((server, helper) => {
    const emptyResponse = { topic_list: { topics: [] } };

    server.get(`/topics/approval-given/${currentUser}.json`, () => {
      return helper.response(emptyResponse);
    });
  });

  test("Shows a blank page placeholder", async function (assert) {
    await visit(`/u/${currentUser}/activity/approval-given`);
    assert.equal(
      query("div.empty-state span.empty-state-title").innerText,
      I18n.t("code_review.approval_given_empty_state_title")
    );
  });
});
