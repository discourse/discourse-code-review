import Component from "@ember/component";
import { LinkTo } from "@ember/routing";
import { classNames, tagName } from "@ember-decorators/component";
import { i18n } from "discourse-i18n";

@tagName("")
@classNames("user-activity-bottom-outlet", "approval-pending-button")
export default class ApprovalPendingButton extends Component {
  <template>
    <LinkTo @route="userActivity.approval-pending">
      {{i18n "code_review.approval_pending"}}
    </LinkTo>
  </template>
}
