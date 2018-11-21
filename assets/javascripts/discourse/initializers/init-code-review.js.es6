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
  api.addPostSmallActionIcon("followup", "clock-o");
  api.addPostSmallActionIcon("approved", "thumbs-up");

  function allowUser() {
    const currentUser = api.getCurrentUser();
    if (!currentUser) {
      return false;
    }
    return currentUser.get("staff");
  }

  api
    .modifySelectKit("topic-footer-mobile-dropdown")
    .modifyContent((context, existingContent) => {
      if (allowUser(context.get("currentUser"))) {
        existingContent.push({
          id: "approve",
          icon: "thumbs-up",
          name: I18n.t("code_review.approve.label")
        });

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
