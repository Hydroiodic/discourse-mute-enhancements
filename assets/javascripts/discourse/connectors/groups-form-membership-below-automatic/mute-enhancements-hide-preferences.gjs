import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// Group → Manage → Membership (admins only): hides Preferences → Notifications and
// Preferences → Users from the group's members. Saved as soon as it is changed, as the page's
// Save button only saves core's fields.
export default class MuteEnhancementsHidePreferences extends Component {
  static shouldRender(args) {
    return (
      !!args.model?.id &&
      args.model.mute_enhancements_hide_preferences !== undefined
    );
  }

  @service toasts;

  @tracked saving = false;

  get group() {
    return this.args.outletArgs.model;
  }

  @action
  async toggle(event) {
    const checkbox = event.target;
    const enabled = checkbox.checked;

    this.saving = true;
    try {
      const result = await ajax(
        `/mute-enhancements/groups/${this.group.id}/hide-preferences`,
        { type: "PUT", data: { enabled } }
      );
      this.group.set(
        "mute_enhancements_hide_preferences",
        result.hide_preferences
      );
      this.toasts.success({
        duration: "short",
        data: {
          message: i18n(
            result.hide_preferences
              ? "mute_enhancements.hide_preferences.turned_on"
              : "mute_enhancements.hide_preferences.turned_off"
          ),
        },
      });
    } catch (error) {
      checkbox.checked = !enabled;
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <div class="control-group mute-enhancements-hide-preferences">
      <label class="control-label">
        {{i18n "mute_enhancements.hide_preferences.title"}}
      </label>
      <label class="checkbox-label">
        <input
          class="mute-enhancements-hide-preferences-checkbox"
          type="checkbox"
          checked={{this.group.mute_enhancements_hide_preferences}}
          disabled={{this.saving}}
          {{on "change" this.toggle}}
        />
        {{i18n "mute_enhancements.hide_preferences.label"}}
      </label>
      <div class="control-instructions">
        {{i18n "mute_enhancements.hide_preferences.description"}}
      </div>
    </div>
  </template>
}
