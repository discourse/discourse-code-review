import { fn } from "@ember/helper";
import RouteTemplate from "ember-route-template";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import htmlSafe from "discourse/helpers/html-safe";
import { i18n } from "discourse-i18n";

export default RouteTemplate(
  <template>
    <h1>{{i18n "code_review.github_webhooks"}}</h1>

    {{#if @controller.organizations}}
      <div class="alert alert-warning">
        {{htmlSafe (i18n "code_review.configure_webhooks_warning")}}
      </div>

      <DButton
        @action={{@controller.configureWebhooks}}
        @label="code_review.configure_webhooks"
        class="code-review-configure-webhooks-button"
        @disabled={{@controller.loadError}}
        @title={{@controller.configureWebhooksTitle}}
      />
    {{else}}
      {{htmlSafe (i18n "code_review.no_organizations_configured")}}
    {{/if}}

    <ConditionalLoadingSpinner @condition={{@controller.loading}}>
      <div class="code-review-webhook-tree">
        {{#each @controller.organizations as |organization|}}
          <div class="code-review-webhook-org">
            <h2>{{organization.name}}</h2>

            {{#each organization.repos as |repo|}}
              <div class="code-review-webhook-repo">
                <h3>{{repo.name}}</h3>

                {{#if repo.receivedWebhookState}}
                  {{#if repo.hasConfiguredWebhook}}
                    <div class="code-review-webhook-configured">
                      {{icon "check"}}
                    </div>
                  {{else}}
                    <div class="code-review-webhook-not-configured">
                      {{icon "xmark"}}
                      <DButton
                        @action={{fn
                          @controller.configureWebhook
                          organization
                          repo
                        }}
                        @label="code_review.configure_webhook"
                      />
                    </div>
                  {{/if}}
                {{/if}}
              </div>
            {{/each}}
          </div>
        {{/each}}
      </div>
    </ConditionalLoadingSpinner>
  </template>
);
