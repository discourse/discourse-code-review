import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance, query } from "discourse/tests/helpers/qunit-helpers";
import { i18n } from "discourse-i18n";

acceptance("User Activity / Approval Given - empty state", function (needs) {
  const currentUser = "eviltrout";
  const anotherUser = "charlie";
  needs.user();

  needs.pretender((server, helper) => {
    const emptyResponse = { topic_list: { topics: [] } };

    server.get(`/topics/approval-given/${currentUser}.json`, () => {
      return helper.response(emptyResponse);
    });

    server.get(`/topics/approval-given/${anotherUser}.json`, () => {
      return helper.response(emptyResponse);
    });
  });

  test("Shows a blank page placeholder on own page", async function (assert) {
    await visit(`/u/${currentUser}/activity/approval-given`);
    assert.equal(
      query(".empty-state .empty-state__title").innerText,
      i18n("code_review.approval_given_empty_state_title")
    );
  });

  test("Shows a blank page placeholder on others' page", async function (assert) {
    await visit(`/u/${anotherUser}/activity/approval-given`);
    assert.equal(
      query(".empty-state .empty-state__title").innerText,
      i18n("code_review.approval_given_empty_state_title_others", {
        username: anotherUser,
      })
    );
  });
});
