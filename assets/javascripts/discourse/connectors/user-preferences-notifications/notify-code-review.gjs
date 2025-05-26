import Component from "@ember/component";
import { classNames, tagName } from "@ember-decorators/component";
import PreferenceCheckbox from "discourse/components/preference-checkbox";
import { i18n } from "discourse-i18n";

@tagName("div")
@classNames("user-preferences-notifications-outlet", "notify-code-review")
export default class NotifyCodeReview extends Component {
  static shouldRender(args, context) {
    return context.currentUser && context.currentUser.admin;
  }

  init() {
    super.init(...arguments);
    const user = this.model;
    this.set(
      "notifyOnCodeReviews",
      user.custom_fields.notify_on_code_reviews !== false
    );
    this.addObserver("notifyOnCodeReviews", () => {
      user.set(
        "custom_fields.notify_on_code_reviews",
        this.get("notifyOnCodeReviews")
      );
    });
  }

  <template>
    <div class="control-group">
      <label class="control-label">{{i18n "code_review.title"}}</label>
      <div class="controls">
        <PreferenceCheckbox
          @labelKey="code_review.notify_on_approval"
          @checked={{this.notifyOnCodeReviews}}
        />
      </div>
    </div>
  </template>
}
