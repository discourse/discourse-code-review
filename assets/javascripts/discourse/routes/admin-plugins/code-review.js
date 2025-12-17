import DiscourseRoute from "discourse/routes/discourse";

export default class AdminPluginsCodeReview extends DiscourseRoute {
  controllerName = "admin-plugins/code-review";

  activate() {
    this.controllerFor(this.controllerName).loadOrganizations();
  }
}
