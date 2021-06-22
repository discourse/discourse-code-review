import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";
import { findAll } from "discourse/models/login-method";
import { computed } from "@ember/object";

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
  api.addPostSmallActionIcon("pr_merge_info", "info-circle");

  // we need to allow unconditional association even with 2fa
  // core hides this section if 2fa is on for a user
  //
  // note there are slightly cleaner ways of doing this but we would need
  // to amend core for the plugin which is not feeling right
  api.modifyClass("controller:preferences/account", {
    canUpdateAssociatedAccounts: computed("authProviders", function () {
      return (
        findAll(this.siteSettings, this.capabilities, this.site.isMobileDevice)
          .length > 0
      );
    }),
  });

  api.modifyClass("controller:preferences/notifications", {
    init() {
      this._super(...arguments);
      this.saveAttrNames.push("custom_fields");
    },
  });

  function allowSkip(currentUser, topic, siteSettings) {
    return allowApprove(currentUser, topic, siteSettings);
  }

  function allowApprove(currentUser, topic, siteSettings) {
    if (!currentUser) {
      return false;
    }

    const allowSelfApprove = siteSettings.code_review_allow_self_approval;
    const approvedTag = siteSettings.code_review_approved_tag;
    const pendingTag = siteSettings.code_review_pending_tag;
    const followupTag = siteSettings.code_review_followup_tag;
    const tags = topic.tags || [];

    return (
      (allowSelfApprove || currentUser.id !== topic.user_id) &&
      !tags.includes(approvedTag) &&
      (tags.includes(pendingTag) || tags.includes(followupTag))
    );
  }

  function allowFollowupButton(topic, siteSettings) {
    if (!siteSettings.code_review_allow_manual_followup) {
      return false;
    }

    const approvedTag = siteSettings.code_review_approved_tag;
    const pendingTag = siteSettings.code_review_pending_tag;
    const followupTag = siteSettings.code_review_followup_tag;

    const tags = topic.tags || [];

    return (
      !tags.includes(followupTag) &&
      (tags.includes(pendingTag) || tags.includes(approvedTag))
    );
  }

  function allowFollowedUpButton(currentUser, topic, siteSettings) {
    const followupTag = siteSettings.code_review_followup_tag;

    const tags = topic.tags || [];

    return currentUser.id === topic.user_id && tags.includes(followupTag);
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
        this.get("currentUser.staff") &&
        allowApprove(this.currentUser, this.topic, this.siteSettings)
      );
    },
  });

  api.registerTopicFooterButton({
    id: "skip",
    icon: "angle-double-right",
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
        this.get("currentUser.staff") &&
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
        this.get("currentUser.staff") &&
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
        this.get("currentUser.staff") &&
        allowFollowedUpButton(this.currentUser, this.topic, this.siteSettings)
      );
    },
  });
}

export default {
  name: "discourse-code-review",

  initialize() {
    withPluginApi("0.8.28", initialize);
  },
};
