import DiscourseRoute from "discourse/routes/discourse";

export default DiscourseRoute.extend({
  controllerName: "admin-plugins-code-review",

  activate() {
    this.controllerFor(this.controllerName).loadOrganizations();
  },
});
