import { createWidgetFrom } from "discourse/widgets/widget";
import { DefaultNotificationItem } from "discourse/widgets/default-notification-item";
import { postUrl } from "discourse/lib/utilities";
import { userPath } from "discourse/lib/url";
import I18n from "I18n";

createWidgetFrom(
  DefaultNotificationItem,
  "code-review-commit-approved-notification-item",
  {
    notificationTitle() {
      return I18n.t("notifications.code_review.commit_approved.title");
    },

    text(notificationName, data) {
      const numApprovedCommits = data.num_approved_commits;

      if (numApprovedCommits === 1) {
        return I18n.t("notifications.code_review.commit_approved.single", {
          topicTitle: this.attrs.fancy_title,
        });
      } else {
        return I18n.t("notifications.code_review.commit_approved.multiple", {
          count: numApprovedCommits,
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
    },
  }
);
