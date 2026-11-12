import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// Group > Manage > User preferences (admins only): turns on enhanced-ignore's "hide topics by
// ignored users" preference for the group's members. Saved as soon as the box is changed.
export default class MuteEnhancementsHideIgnoredTopics extends Component {
  @service toasts;

  @tracked saving = false;

  get checked() {
    return this.args.group.mute_enhancements_hide_ignored_topics;
  }

  @action
  async toggle(event) {
    const checkbox = event.target;

    this.saving = true;
    try {
      const result = await ajax(
        `/mute-enhancements/groups/${this.args.group.id}/hide-ignored-topics`,
        { type: "PUT", data: { enabled: checkbox.checked } }
      );
      this.args.group.set(
        "mute_enhancements_hide_ignored_topics",
        result.hide_ignored_topics
      );

      this.toasts.success({
        duration: "short",
        data: {
          message:
            result.applied_user_count > 0
              ? i18n(
                  "mute_enhancements.hide_ignored_topics.saved_and_applied",
                  {
                    count: result.applied_user_count,
                  }
                )
              : i18n("mute_enhancements.hide_ignored_topics.saved"),
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
    <div class="control-group mute-enhancements-hide-ignored-topics">
      <label class="control-label">
        {{i18n "mute_enhancements.hide_ignored_topics.title"}}
      </label>
      <div class="control-instructions">
        {{i18n "mute_enhancements.hide_ignored_topics.description"}}
      </div>
      <label class="checkbox-label">
        <input
          class="mute-enhancements-hide-ignored-topics-input"
          type="checkbox"
          checked={{this.checked}}
          disabled={{this.saving}}
          {{on "change" this.toggle}}
        />
        {{i18n "mute_enhancements.hide_ignored_topics.label"}}
      </label>
    </div>
  </template>
}
