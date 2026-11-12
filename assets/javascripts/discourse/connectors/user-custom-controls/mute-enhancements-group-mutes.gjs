import Component from "@glimmer/component";
import { action, get } from "@ember/object";
import { service } from "@ember/service";
import GroupChooser from "discourse/select-kit/components/group-chooser";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

function parseIds(value) {
  return (value || "")
    .split(",")
    .filter(Boolean)
    .map((id) => parseInt(id, 10));
}

// Preferences → Users: groups whose members the user mutes or ignores. The lists are saved with
// the page's Save button (see api-initializers/mute-enhancements.js). Core renders this outlet on
// most preference pages, so the connector only shows itself on Users, the page that saves them.
export default class MuteEnhancementsGroupMutes extends Component {
  static shouldRender(args) {
    return args.model?.mute_enhancements_available_groups !== undefined;
  }

  @service router;

  get model() {
    return this.args.outletArgs.model;
  }

  get onUsersPage() {
    return this.router.currentRouteName === "preferences.users";
  }

  // The model is a classic object updated with set(), so read with get() for the getters to
  // update when the choosers change it.
  get mutedIds() {
    return parseIds(get(this.model, "mute_enhancements_muted_group_ids"));
  }

  get ignoredIds() {
    return parseIds(get(this.model, "mute_enhancements_ignored_group_ids"));
  }

  // A group is either muted or ignored, so each list leaves out the groups in the other one.
  get mutableGroups() {
    return this.model.mute_enhancements_available_groups.filter(
      (group) => !this.ignoredIds.includes(group.id)
    );
  }

  get ignorableGroups() {
    return this.model.mute_enhancements_available_groups.filter(
      (group) => !this.mutedIds.includes(group.id)
    );
  }

  @action
  onChangeMuted(ids) {
    this.model.set("mute_enhancements_muted_group_ids", ids.join(","));
  }

  @action
  onChangeIgnored(ids) {
    this.model.set("mute_enhancements_ignored_group_ids", ids.join(","));
  }

  <template>
    {{#if this.onUsersPage}}
      {{#if this.model.can_ignore_users}}
        <div
          class="control-group mute-enhancements-ignored-groups"
          data-setting-name="mute-enhancements-ignored-groups"
        >
          <div class="controls tracking-controls">
            <label>
              {{dIcon "far-eye-slash" class="icon"}}
              <span>{{i18n
                  "mute_enhancements.group_mutes.ignored_groups"
                }}</span>
            </label>
            <GroupChooser
              @content={{this.ignorableGroups}}
              @labelProperty="name"
              @onChange={{this.onChangeIgnored}}
              @value={{this.ignoredIds}}
            />
          </div>
          <div class="instructions">
            {{i18n "mute_enhancements.group_mutes.ignored_groups_instructions"}}
          </div>
        </div>
      {{/if}}

      {{#if this.model.can_mute_users}}
        <div
          class="control-group mute-enhancements-muted-groups"
          data-setting-name="mute-enhancements-muted-groups"
        >
          <div class="controls tracking-controls">
            <label>
              {{dIcon "d-muted" class="icon"}}
              <span>{{i18n "mute_enhancements.group_mutes.muted_groups"}}</span>
            </label>
            <GroupChooser
              @content={{this.mutableGroups}}
              @labelProperty="name"
              @onChange={{this.onChangeMuted}}
              @value={{this.mutedIds}}
            />
          </div>
          <div class="instructions">
            {{i18n "mute_enhancements.group_mutes.muted_groups_instructions"}}
          </div>
        </div>
      {{/if}}
    {{/if}}
  </template>
}
