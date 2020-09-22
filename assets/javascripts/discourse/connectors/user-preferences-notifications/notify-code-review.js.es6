export default {
  //setupComponent(args, component) {},
  shouldRender(args, component) {
    return component.currentUser && component.currentUser.admin;
  },
};
