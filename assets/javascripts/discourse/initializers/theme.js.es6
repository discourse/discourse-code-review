import discourseComputed from "discourse-common/utils/decorators";
import TopicListComponent from "discourse/components/topic-list";
import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "discourse-code-review-theme",

  initialize(container) {
    const siteSettings = container.lookup("site-settings:main");
    if (!siteSettings.code_review_theme) {
      return;
    }

    withPluginApi("0.8.28", () => {
      TopicListComponent.reopen({
        @discourseComputed("filteredTopics.[]")
        filteredTopicsByDate(filteredTopics) {
          if (
            !this.category ||
            !this.category.custom_fields["GitHub Repo Name"]
          ) {
            return;
          }

          const topicsByDate = {};
          filteredTopics.forEach(topic => {
            topic.setProperties({
              approved: topic.tags.includes(
                this.siteSettings.code_review_approved_tag
              ),
              followup: topic.tags.includes(
                this.siteSettings.code_review_followup_tag
              ),
              pending: topic.tags.includes(
                this.siteSettings.code_review_pending_tag
              )
            });

            const date = moment(topic.created_at).format("YYYY-MM-DD");
            if (!topicsByDate[date]) {
              topicsByDate[date] = [];
            }
            topicsByDate[date].push(topic);
          });

          const filteredTopicsByDate = [];
          Object.keys(topicsByDate)
            .sort()
            .reverse()
            .forEach(date => {
              filteredTopicsByDate.push({
                date: moment(date).format("MMMM D, YYYY"),
                topics: topicsByDate[date]
              });
            });
          return filteredTopicsByDate;
        }
      });
    });
  }
};
