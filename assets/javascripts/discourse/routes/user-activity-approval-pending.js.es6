import UserTopicListRoute from "discourse/routes/user-topic-list";

export default UserTopicListRoute.extend({
  model: function() {
    return this.store.findFiltered("topicList", {
      filter: `topics/approval-pending/${this.modelFor("user").get(
        "username_lower"
      )}`
    });
  }
});
