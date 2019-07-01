import UserTopicListRoute from "discourse/routes/user-topic-list";

export default UserTopicListRoute.extend({
  model: function() {
    return this.store.findFiltered("topicList", {
      filter: `topics/approval-given/${this.modelFor("user").get("username_lower")}`
    });
  }
});
