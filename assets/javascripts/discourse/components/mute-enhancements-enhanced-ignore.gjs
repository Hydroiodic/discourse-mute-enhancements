import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// In the order of enhanced-ignore's own preferences.
const OPTIONS = ["hide_ignored_topics", "ignored_user_cannot_reply_to_me"];

// Group > Manage > User preferences (admins only): enhanced-ignore's options turned on for the
// group's members, each on its own. Saved as soon as a box is changed.
export default class MuteEnhancementsEnhancedIgnore extends Component {
  @service toasts;

  @tracked saving = false;

  get enabled() {
    return this.args.group.mute_enhancements_enhanced_ignore;
  }

  get options() {
    return OPTIONS.map((option) => ({
      option,
      checked: this.enabled.includes(option),
      label: i18n(`mute_enhancements.enhanced_ignore.options.${option}`),
    }));
  }

  @action
  async toggle(option, event) {
    const checkbox = event.target;
    const options = checkbox.checked
      ? [...this.enabled, option]
      : this.enabled.filter((enabled) => enabled !== option);

    this.saving = true;
    try {
      const result = await ajax(
        `/mute-enhancements/groups/${this.args.group.id}/enhanced-ignore`,
        { type: "PUT", data: { options: options.join(",") } }
      );
      this.args.group.set(
        "mute_enhancements_enhanced_ignore",
        result.enhanced_ignore
      );

      this.toasts.success({
        duration: "short",
        data: {
          message:
            result.applied_user_count > 0
              ? i18n("mute_enhancements.enhanced_ignore.saved_and_applied", {
                  count: result.applied_user_count,
                })
              : i18n("mute_enhancements.enhanced_ignore.saved"),
        },
      });
    } catch (error) {
      checkbox.checked = !checkbox.checked;
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <div class="control-group mute-enhancements-enhanced-ignore">
      <label class="control-label">
        {{i18n "mute_enhancements.enhanced_ignore.title"}}
      </label>
      {{#each this.options as |item|}}
        <label class="checkbox-label">
          <input
            class="mute-enhancements-enhanced-ignore-{{item.option}}"
            type="checkbox"
            checked={{item.checked}}
            disabled={{this.saving}}
            {{on "change" (fn this.toggle item.option)}}
          />
          {{item.label}}
        </label>
      {{/each}}
    </div>
  </template>
}
