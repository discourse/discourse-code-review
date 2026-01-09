import { computed } from "@ember/object";
import { htmlSafe } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { withPluginApi } from "discourse/lib/plugin-api";
import DiscourseURL, { userPath } from "discourse/lib/url";
import { findAll } from "discourse/models/login-method";
import { i18n } from "discourse-i18n";

async function actOnCommit(topic, action) {
  try {
    let result = await ajax(`/code-review/${action}.json`, {
      type: "POST",
      data: { topic_id: topic.id },
    });

    if (result.next_topic_url) {
      DiscourseURL.routeTo(result.next_topic_url);
    } else {
      DiscourseURL.routeTo("/");
    }
  } catch (error) {
    popupAjaxError(error);
  }
}

function initialize(api) {
  api.addPostSmallActionIcon("followup", "far-clock");
  api.addPostSmallActionIcon("approved", "thumbs-up");
  api.addPostSmallActionIcon("followed_up", "backward");
  api.addPostSmallActionIcon("pr_merge_info", "circle-info");

  // we need to allow unconditional association even with 2fa
  // core hides this section if 2fa is on for a user
  //
  // note there are slightly cleaner ways of doing this but we would need
  // to amend core for the plugin which is not feeling right
  api.modifyClass(
    "controller:preferences/account",
    (Superclass) =>
      class extends Superclass {
        @computed("authProviders")
        get canUpdateAssociatedAccounts() {
          return findAll().length > 0;
        }
      }
  );

  api.addSaveableCustomFields("notifications");

  function allowSkip(currentUser, topic, siteSettings) {
    return allowApprove(currentUser, topic, siteSettings);
  }

  function getTagNames(topic) {
    return (topic.tags || []).map((t) => (typeof t === "string" ? t : t.name));
  }

  function allowApprove(currentUser, topic, siteSettings) {
    if (!currentUser) {
      return false;
    }

    const allowSelfApprove = siteSettings.code_review_allow_self_approval;
    const approvedTag = siteSettings.code_review_approved_tag;
    const pendingTag = siteSettings.code_review_pending_tag;
    const followupTag = siteSettings.code_review_followup_tag;
    const tagNames = getTagNames(topic);

    return (
      (allowSelfApprove || currentUser.id !== topic.user_id) &&
      !tagNames.includes(approvedTag) &&
      (tagNames.includes(pendingTag) || tagNames.includes(followupTag))
    );
  }

  function allowFollowupButton(topic, siteSettings) {
    if (!siteSettings.code_review_allow_manual_followup) {
      return false;
    }

    const approvedTag = siteSettings.code_review_approved_tag;
    const pendingTag = siteSettings.code_review_pending_tag;
    const followupTag = siteSettings.code_review_followup_tag;

    const tagNames = getTagNames(topic);

    return (
      !tagNames.includes(followupTag) &&
      (tagNames.includes(pendingTag) || tagNames.includes(approvedTag))
    );
  }

  function allowFollowedUpButton(currentUser, topic, siteSettings) {
    const followupTag = siteSettings.code_review_followup_tag;

    const tagNames = getTagNames(topic);

    return currentUser.id === topic.user_id && tagNames.includes(followupTag);
  }

  api.registerTopicFooterButton({
    id: "approve",
    icon: "thumbs-up",
    priority: 260,
    label: "code_review.approve.label",
    title: "code_review.approve.title",
    action() {
      actOnCommit(this.topic, "approve");
    },
    dropdown() {
      return this.site.mobileView;
    },
    classNames: ["approve"],
    dependentKeys: ["topic.tags"],
    displayed() {
      return (
        this.get("currentUser.can_review_code") &&
        allowApprove(this.currentUser, this.topic, this.siteSettings)
      );
    },
  });

  api.registerTopicFooterButton({
    id: "skip",
    icon: "angles-right",
    priority: 250,
    label: "code_review.skip.label",
    title: "code_review.skip.title",
    action() {
      actOnCommit(this.topic, "skip");
    },
    dropdown() {
      return this.site.mobileView;
    },
    classNames: ["skip"],
    dependentKeys: ["topic.tags"],
    displayed() {
      return (
        this.get("currentUser.can_review_code") &&
        allowSkip(this.currentUser, this.topic, this.siteSettings)
      );
    },
  });

  api.registerTopicFooterButton({
    id: "followup",
    icon: "far-clock",
    priority: 240,
    label: "code_review.followup.label",
    title: "code_review.followup.title",
    action() {
      actOnCommit(this.topic, "followup");
    },
    dropdown() {
      return this.site.mobileView;
    },
    classNames: ["followup"],
    dependentKeys: ["topic.tags"],
    displayed() {
      return (
        this.get("currentUser.can_review_code") &&
        allowFollowupButton(this.topic, this.siteSettings)
      );
    },
  });

  api.registerTopicFooterButton({
    id: "followed_up",
    icon: "history",
    priority: 240,
    label: "code_review.followed_up.label",
    title: "code_review.followed_up.title",
    action() {
      actOnCommit(this.topic, "followed_up");
    },
    dropdown() {
      return this.site.mobileView;
    },
    classNames: ["followup"],
    dependentKeys: ["topic.tags"],
    displayed() {
      return (
        this.get("currentUser.can_review_code") &&
        allowFollowedUpButton(this.currentUser, this.topic, this.siteSettings)
      );
    },
  });

  api.replaceIcon("notification.code_review_commit_approved", "check");

  api.addKeyboardShortcut("y", function () {
    if (
      !this.currentUser?.can_review_code ||
      !allowApprove(this.currentUser, this.currentTopic(), this.siteSettings)
    ) {
      return;
    }
    actOnCommit(this.currentTopic(), "approve");
  });

  if (api.registerNotificationTypeRenderer) {
    api.registerNotificationTypeRenderer(
      "code_review_commit_approved",
      (NotificationTypeBase) => {
        return class extends NotificationTypeBase {
          get linkTitle() {
            return i18n("notifications.code_review.commit_approved.title");
          }

          get icon() {
            return "check";
          }

          get linkHref() {
            return (
              super.linkHref ||
              userPath(`${this.currentUser.username}/activity/approval-given`)
            );
          }

          get label() {
            const numApprovedCommits =
              this.notification.data.num_approved_commits;
            if (numApprovedCommits > 1) {
              return i18n(
                "notifications.code_review.commit_approved.multiple",
                {
                  count: numApprovedCommits,
                }
              );
            } else {
              return htmlSafe(
                i18n("notifications.code_review.commit_approved.single", {
                  topicTitle: this.notification.fancy_title,
                })
              );
            }
          }

          get description() {
            return null;
          }
        };
      }
    );
  }
}

export default {
  name: "discourse-code-review",

  initialize() {
    withPluginApi(initialize);
  },
};
