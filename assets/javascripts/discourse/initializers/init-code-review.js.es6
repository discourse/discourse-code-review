import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";

function actOnCommit(topic, action) {
  let topicId = topic.get("id");
  return ajax(`/code-review/${action}.json`, {
    type: "POST",
    data: { topic_id: topicId }
  })
    .then(result => {
      if (result.next_topic_url) {
        DiscourseURL.routeTo(result.next_topic_url);
      }
    })
    .catch(popupAjaxError);
}

function initialize(api) {
  api.addPostSmallActionIcon("followup", "far-clock");
  api.addPostSmallActionIcon("approved", "thumbs-up");

  // we need to allow unconditional association even with 2fa
  // core hides this section if 2fa is on for a user
  api.modifyClass("controller:preferences/account", {
    canUpdateAssociatedAccounts: function() {
      return this.get("authProviders.length") > 0;
    }.property("authProviders")
  });

  function allowUser() {
    const currentUser = api.getCurrentUser();
    if (!currentUser) {
      return false;
    }
    return currentUser.get("staff");
  }

  function allowApprove(topic) {
    const currentUser = api.getCurrentUser();
    if (!currentUser) {
      return false;
    }

    const siteSettings = api.container.lookup("site-settings:main");
    const allowSelfApprove = siteSettings.code_review_allow_self_approval;
    const approvedTag = siteSettings.code_review_approved_tag;
    const tags = topic.get("tags") || [];

    return (
      (allowSelfApprove || currentUser.get("id") !== topic.get("user_id")) &&
      !tags.includes(approvedTag)
    );
  }

  function allowFollowup(topic) {
    const followupTag = api.container.lookup("site-settings:main")
      .code_review_followup_tag;
    const tags = topic.get("tags") || [];

    return !tags.includes(followupTag);
  }

  api
    .modifySelectKit("topic-footer-mobile-dropdown")
    .modifyContent((context, existingContent) => {
      const topic = context.get("topic");

      if (allowUser()) {
        if (allowApprove(topic))
          existingContent.push({
            id: "approve",
            icon: "thumbs-up",
            name: I18n.t("code_review.approve.label")
          });

        if (allowFollowup(topic))
          existingContent.push({
            id: "followup",
            icon: "clock-o",
            name: I18n.t("code_review.followup.label")
          });
      }
      return existingContent;
    })
    .onSelect((context, value) => {
      if (value === "approve" || value === "followup") {
        const topic = context.get("topic");
        actOnCommit(topic, value);
        return true;
      }
    });

  api.registerConnectorClass(
    "topic-footer-main-buttons-before-create",
    "approve",
    {
      setupComponent(args) {
        this.set("topic", args.topic);
        this.set("showApprove", allowApprove(args.topic));
        this.set("showFollowup", allowFollowup(args.topic));
      },
      shouldRender: function(args, component) {
        if (component.get("site.mobileView")) {
          return false;
        }
        return allowUser(args.topic);
      },

      actions: {
        followupCommit() {
          actOnCommit(this.get("topic"), "followup");
        },
        approveCommit() {
          actOnCommit(this.get("topic"), "approve");
        }
      }
    }
  );
}

export default {
  name: "discourse-code-review",

  initialize() {
    withPluginApi("0.8.7", initialize);
  }
};
