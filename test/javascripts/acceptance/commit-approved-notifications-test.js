import { acceptance, queryAll } from "discourse/tests/helpers/qunit-helpers";
import { test } from "qunit";
import { click, visit } from "@ember/test-helpers";
import I18n from "I18n";

acceptance("Discourse Code Review - Notifications", function (needs) {
  needs.user({ redesigned_user_menu_enabled: true });

  needs.pretender((server, helper) => {
    server.get("/notifications", () => {
      return helper.response({
        notifications: [
          {
            id: 801,
            user_id: 12,
            notification_type: 21, // code_review_commit_approved notification type
            read: true,
            high_priority: false,
            created_at: "2001-10-17 15:41:10 UTC",
            post_number: 1,
            topic_id: 883,
            fancy_title: "Osama's commit #1",
            slug: "osama-s-commit-1",
            data: {
              num_approved_commits: 1,
            },
          },
          {
            id: 389,
            user_id: 12,
            notification_type: 21, // code_review_commit_approved notification type
            read: true,
            high_priority: false,
            created_at: "2010-11-17 23:01:15 UTC",
            post_number: null,
            topic_id: null,
            fancy_title: null,
            slug: null,
            data: {
              num_approved_commits: 10,
            },
          },
        ],
      });
    });
  });

  test("code review commit approved notifications", async function (assert) {
    await visit("/");
    await click(".d-header-icons .current-user");

    const notifications = queryAll(
      "#quick-access-all-notifications ul li.notification a"
    );
    assert.strictEqual(notifications.length, 2);

    assert.strictEqual(
      notifications[0].textContent.replaceAll(/\s+/g, " ").trim(),
      I18n.t("notifications.code_review.commit_approved.single", {
        topicTitle: "Osama's commit #1",
      }),
      "notification for a single commit approval has the right content"
    );
    assert.ok(
      notifications[0].href.endsWith("/t/osama-s-commit-1/883"),
      "notification for a single commit approval links to the topic"
    );
    assert.ok(
      notifications[0].querySelector(".d-icon-check"),
      "notification for a single commit approval has the right icon"
    );

    assert.strictEqual(
      notifications[1].textContent.replaceAll(/\s+/g, " ").trim(),
      I18n.t("notifications.code_review.commit_approved.multiple", {
        count: 10,
      }),
      "notification for multiple commits approval has the right content"
    );
    assert.ok(
      notifications[1].href.endsWith("/u/eviltrout/activity/approval-given"),
      "notification for multiple commits approval links to the user approval-given page"
    );
    assert.ok(
      notifications[1].querySelector(".d-icon-check"),
      "notification for multiple commits approval has the right icon"
    );
  });
});
