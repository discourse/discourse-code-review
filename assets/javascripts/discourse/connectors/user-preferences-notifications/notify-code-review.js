export default {
  setupComponent(args, component) {
    const user = args.model;
    this.set(
      "notifyOnCodeReviews",
      user.custom_fields.notify_on_code_reviews !== false
    );

    component.addObserver("notifyOnCodeReviews", () => {
      user.set(
        "custom_fields.notify_on_code_reviews",
        component.get("notifyOnCodeReviews")
      );
    });
  },
  shouldRender(args, component) {
    return component.currentUser && component.currentUser.admin;
  },
};
