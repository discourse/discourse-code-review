import Component from "@ember/component";
import { LinkTo } from "@ember/routing";
import { classNames, tagName } from "@ember-decorators/component";
import { i18n } from "discourse-i18n";

@tagName("")
@classNames("user-activity-bottom-outlet", "approval-given-button")
export default class ApprovalGivenButton extends Component {
  <template>
    <LinkTo @route="userActivity.approval-given">
      {{i18n "code_review.approval_given"}}
    </LinkTo>
  </template>
}
