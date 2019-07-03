import { createWidgetFrom } from "discourse/widgets/widget";
import { DefaultNotificationItem } from "discourse/widgets/default-notification-item";
import { replaceIcon } from "discourse-common/lib/icon-library";

replaceIcon("notification.code_review_commit_approved", "check");

createWidgetFrom(
  DefaultNotificationItem,
  "code-review-commit-approved-notification-item",
  {
    notificationTitle() {
      return I18n.t("notifications.code_review.commit_approved.title");
    },

    text(notificationName, data) {
      const num_approved_commits = data.num_approved_commits;

      if (num_approved_commits === 1) {
        return I18n.t("notifications.code_review.commit_approved.one");
      } else {
        return I18n.t("notifications.code_review.commit_approved.many", {
          num_approved_commits
        });
      }
    }
  }
);
