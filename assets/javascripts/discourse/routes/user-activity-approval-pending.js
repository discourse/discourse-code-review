import UserTopicListRoute from "discourse/routes/user-topic-list";
import I18n from "I18n";

export default UserTopicListRoute.extend({
  model() {
    const username = this.modelFor("user").username_lower;
    return this.store
      .findFiltered("topicList", {
        filter: `topics/approval-pending/${username}`,
      })
      .then((model) => {
        // andrei: we agreed that this is an anti pattern,
        // it's better to avoid mutating a rest model like this
        // this place we'll be refactored later
        // see https://github.com/discourse/discourse/pull/14313#discussion_r708784704
        model.set("emptyState", this.emptyState());
        return model;
      });
  },

  emptyState() {
    const title = I18n.t("code_review.approval_pending_empty_state_title");
    const body = "";
    return { title, body };
  },
});
