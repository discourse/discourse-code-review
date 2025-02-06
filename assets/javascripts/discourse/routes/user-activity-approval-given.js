import UserTopicListRoute from "discourse/routes/user-topic-list";
import { i18n } from "discourse-i18n";

export default class UserActivityApprovalGiven extends UserTopicListRoute {
  model() {
    const username = this.modelFor("user").username_lower;
    return this.store
      .findFiltered("topicList", {
        filter: `topics/approval-given/${username}`,
      })
      .then((model) => {
        // andrei: we agreed that this is an anti pattern,
        // it's better to avoid mutating a rest model like this
        // this place we'll be refactored later
        // see https://github.com/discourse/discourse/pull/14313#discussion_r708784704
        model.set("emptyState", this.emptyState());
        return model;
      });
  }

  emptyState() {
    const user = this.modelFor("user");
    let title;

    if (this.isCurrentUser(user)) {
      title = i18n("code_review.approval_given_empty_state_title");
    } else {
      title = i18n("code_review.approval_given_empty_state_title_others", {
        username: user.username,
      });
    }
    const body = "";
    return { title, body };
  }
}
