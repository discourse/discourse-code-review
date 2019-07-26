import { createWidgetFrom } from "discourse/widgets/widget";
import { DefaultNotificationItem } from "discourse/widgets/default-notification-item";
import { replaceIcon } from "discourse-common/lib/icon-library";
import { postUrl } from "discourse/lib/utilities";
import { userPath } from "discourse/lib/url";
import { i18n } from "discourse/lib/computed";

replaceIcon("notification.code_review_commit_approved", "check");

createWidgetFrom(
  DefaultNotificationItem,
  "code-review-commit-approved-notification-item",
  {
    notificationTitle: i18n("notifications.code_review.commit_approved.title"),

    text(notificationName, data) {
      const numApprovedCommits = data.num_approved_commits;

      if (numApprovedCommits === 1) {
        return I18n.t("notifications.code_review.commit_approved.single", {
          topicTitle: this.attrs.fancy_title
        });
      } else {
        return I18n.t("notifications.code_review.commit_approved.multiple", {
          numApprovedCommits
        });
      }
    },

    url() {
      const topicId = this.attrs.topic_id;

      if (topicId) {
        return postUrl(this.attrs.slug, topicId, 1);
      } else {
        return userPath(`${this.currentUser.username}/activity/approval-given`);
      }
    }
  }
);
