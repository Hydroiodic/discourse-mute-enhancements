import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

// In the order of the preferences nav.
const PAGES = ["tracking", "users"];

// Group → Manage → User preferences (admins only): preference pages hidden from the group's
// members, each on its own. Saved as soon as a box is changed.
export default class MuteEnhancementsHidePreferences extends Component {
  @service toasts;

  @tracked saving = false;

  get hidden() {
    return this.args.group.mute_enhancements_hidden_preferences;
  }

  get pages() {
    return PAGES.map((page) => ({
      page,
      checked: this.hidden.includes(page),
      label: i18n(`mute_enhancements.hide_preferences.pages.${page}`),
    }));
  }

  @action
  async toggle(page, event) {
    const checkbox = event.target;
    const pages = checkbox.checked
      ? [...this.hidden, page]
      : this.hidden.filter((hidden) => hidden !== page);

    this.saving = true;
    try {
      const result = await ajax(
        `/mute-enhancements/groups/${this.args.group.id}/hide-preferences`,
        { type: "PUT", data: { hidden_pages: pages.join(",") } }
      );
      this.args.group.set(
        "mute_enhancements_hidden_preferences",
        result.hidden_preferences
      );
      this.toasts.success({
        duration: "short",
        data: { message: i18n("mute_enhancements.hide_preferences.saved") },
      });
    } catch (error) {
      checkbox.checked = !checkbox.checked;
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
      <div class="control-instructions">
        {{i18n "mute_enhancements.hide_preferences.description"}}
      </div>
      {{#each this.pages as |item|}}
        <label class="checkbox-label">
          <input
            class="mute-enhancements-hide-preferences-{{item.page}}"
            type="checkbox"
            checked={{item.checked}}
            disabled={{this.saving}}
            {{on "change" (fn this.toggle item.page)}}
          />
          {{item.label}}
        </label>
      {{/each}}
    </div>
  </template>
}
