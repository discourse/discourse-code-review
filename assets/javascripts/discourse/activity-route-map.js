export default {
  resource: "user.userActivity",

  map() {
    this.route("approval-given");
    this.route("approval-pending");
  },
};
