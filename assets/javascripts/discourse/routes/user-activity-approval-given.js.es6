import UserTopicListRoute from "discourse/routes/user-topic-list";

export default UserTopicListRoute.extend({
  model() {
    const username = this.modelFor("user").username_lower;
    return this.store.findFiltered("topicList", {
      filter: `topics/approval-given/${username}`,
    });
  },
});
