import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";

function initialize(api) {
  api.addPostSmallActionIcon("approved", "thumbs-up");
  api.registerConnectorClass(
    "topic-footer-main-buttons-before-create",
    "approve",
    {
      setupComponent(args) {
        this.set("topic", args.topic);
      },
      actions: {
        approveCommit() {
          let topicId = this.get("topic.id");
          return ajax("/code-review/approve.json", {
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
