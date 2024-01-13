import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance, query } from "discourse/tests/helpers/qunit-helpers";
import I18n from "I18n";

acceptance("User Activity / Approval Pending - empty state", function (needs) {
  const currentUser = "eviltrout";
  const anotherUser = "charlie";
  needs.user();

  needs.pretender((server, helper) => {
    const emptyResponse = { topic_list: { topics: [] } };

    server.get(`/topics/approval-pending/${currentUser}.json`, () => {
      return helper.response(emptyResponse);
    });

    server.get(`/topics/approval-pending/${anotherUser}.json`, () => {
      return helper.response(emptyResponse);
    });
  });

  test("Shows a blank page placeholder on own page", async function (assert) {
    await visit(`/u/${currentUser}/activity/approval-pending`);
    assert.equal(
      query("div.empty-state span.empty-state-title").innerText,
      I18n.t("code_review.approval_pending_empty_state_title")
    );
  });

  test("Shows a blank page placeholder on others' page", async function (assert) {
    await visit(`/u/${anotherUser}/activity/approval-pending`);
    assert.equal(
      query("div.empty-state span.empty-state-title").innerText,
      I18n.t("code_review.approval_pending_empty_state_title_others", {
        username: anotherUser,
      })
    );
  });
});
