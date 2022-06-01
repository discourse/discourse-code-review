import { findRawTemplate } from "discourse-common/lib/raw-templates";
import { observes } from "discourse-common/utils/decorators";
import TopicListItem from "discourse/components/topic-list-item";
import { htmlSafe } from "@ember/template";

export default TopicListItem.extend({
  @observes("topic.pinned")
  renderTopicListItem() {
    const template = findRawTemplate("list/review-topic-list-item");
    if (template) {
      this.set("topicListItemContents", htmlSafe(template(this)));
    }
  },
});
