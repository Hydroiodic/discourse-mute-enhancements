import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import GroupDefaultNotificationsModal from "discourse/components/modal/group-default-notifications";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import GroupChooser from "discourse/select-kit/components/group-chooser";
import UserChooser from "discourse/select-kit/components/user-chooser";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const NO_GROUPS = { muted_group_ids: [], ignored_group_ids: [] };

function sameItems(a, b) {
  return [...a].sort().join(",") === [...b].sort().join(",");
}

function addedItems(current, saved) {
  return current.filter((item) => !saved.includes(item)).length;
}

// Group > Manage > Member preferences (admins only): users, and groups when group mutes are
// enabled, that members of the group mute or ignore by default. Has its own Save button, as the
// hidden pages on the same page are saved as soon as they change.
export default class MuteEnhancementsDefaultUsers extends Component {
  @service modal;
  @service toasts;

  @tracked muted = [...this.saved.muted_usernames];
  @tracked ignored = [...this.saved.ignored_usernames];
  @tracked mutedGroupIds = [...this.savedGroups.muted_group_ids];
  @tracked ignoredGroupIds = [...this.savedGroups.ignored_group_ids];
  @tracked saving = false;

  get group() {
    return this.args.group;
  }

  get saved() {
    return this.group.mute_enhancements_default_users;
  }

  // Missing when group mutes are disabled.
  get withGroups() {
    return this.group.mute_enhancements_default_groups !== undefined;
  }

  get savedGroups() {
    return this.group.mute_enhancements_default_groups ?? NO_GROUPS;
  }

  // A group is either muted or ignored, so each list leaves out the groups in the other one.
  get mutableGroups() {
    return this.savedGroups.available_groups.filter(
      (group) => !this.ignoredGroupIds.includes(group.id)
    );
  }

  get ignorableGroups() {
    return this.savedGroups.available_groups.filter(
      (group) => !this.mutedGroupIds.includes(group.id)
    );
  }

  get dirty() {
    return (
      !sameItems(this.muted, this.saved.muted_usernames) ||
      !sameItems(this.ignored, this.saved.ignored_usernames) ||
      !sameItems(this.mutedGroupIds, this.savedGroups.muted_group_ids) ||
      !sameItems(this.ignoredGroupIds, this.savedGroups.ignored_group_ids)
    );
  }

  // Defaults that are new or moved between muted and ignored; only these can be given to
  // current members.
  get addedCount() {
    return (
      addedItems(this.muted, this.saved.muted_usernames) +
      addedItems(this.ignored, this.saved.ignored_usernames) +
      addedItems(this.mutedGroupIds, this.savedGroups.muted_group_ids) +
      addedItems(this.ignoredGroupIds, this.savedGroups.ignored_group_ids)
    );
  }

  @action
  onChangeMuted(usernames) {
    this.muted = usernames;
  }

  @action
  onChangeIgnored(usernames) {
    this.ignored = usernames;
  }

  @action
  onChangeMutedGroups(ids) {
    this.mutedGroupIds = ids;
  }

  @action
  onChangeIgnoredGroups(ids) {
    this.ignoredGroupIds = ids;
  }

  @action
  async save() {
    let updateExistingUsers = false;

    if (this.addedCount > 0 && this.group.user_count > 0) {
      updateExistingUsers = await this.modal.show(
        GroupDefaultNotificationsModal,
        { model: { count: this.group.user_count } }
      );
      if (updateExistingUsers === undefined) {
        return;
      }
    }

    const data = {
      muted_usernames: this.muted.join(","),
      ignored_usernames: this.ignored.join(","),
      update_existing_users: updateExistingUsers,
    };
    if (this.withGroups) {
      data.muted_group_ids = this.mutedGroupIds.join(",");
      data.ignored_group_ids = this.ignoredGroupIds.join(",");
    }

    this.saving = true;
    try {
      const result = await ajax(
        `/mute-enhancements/groups/${this.group.id}/default-users`,
        { type: "PUT", data }
      );

      this.group.set("mute_enhancements_default_users", {
        muted_usernames: result.muted_usernames,
        ignored_usernames: result.ignored_usernames,
      });
      this.muted = [...result.muted_usernames];
      this.ignored = [...result.ignored_usernames];

      if (this.withGroups) {
        this.group.set("mute_enhancements_default_groups", {
          ...this.savedGroups,
          muted_group_ids: result.muted_group_ids,
          ignored_group_ids: result.ignored_group_ids,
        });
        this.mutedGroupIds = [...result.muted_group_ids];
        this.ignoredGroupIds = [...result.ignored_group_ids];
      }

      this.toasts.success({
        duration: "short",
        data: {
          message: updateExistingUsers
            ? i18n("mute_enhancements.default_users.saved_and_applied", {
                count: result.applied_user_count,
              })
            : i18n("mute_enhancements.default_users.saved"),
        },
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <div class="control-group mute-enhancements-default-users">
      <label class="control-label">
        {{#if this.withGroups}}
          {{i18n "mute_enhancements.default_users.title_with_groups"}}
        {{else}}
          {{i18n "mute_enhancements.default_users.title"}}
        {{/if}}
      </label>
      <div class="control-instructions">
        {{#if this.withGroups}}
          {{i18n "mute_enhancements.default_users.description_with_groups"}}
        {{else}}
          {{i18n "mute_enhancements.default_users.description"}}
        {{/if}}
      </div>

      <label>
        {{dIcon "far-eye-slash"}}
        {{i18n "mute_enhancements.default_users.ignored"}}
      </label>
      <UserChooser
        class="mute-enhancements-default-ignored-users"
        @onChange={{this.onChangeIgnored}}
        @options={{hash excludedUsernames=this.muted}}
        @value={{this.ignored}}
      />

      {{#if this.withGroups}}
        <label>
          {{dIcon "far-eye-slash"}}
          {{i18n "mute_enhancements.default_users.ignored_groups"}}
        </label>
        <GroupChooser
          class="mute-enhancements-default-ignored-groups"
          @content={{this.ignorableGroups}}
          @labelProperty="name"
          @onChange={{this.onChangeIgnoredGroups}}
          @value={{this.ignoredGroupIds}}
        />
      {{/if}}

      <label>
        {{dIcon "d-muted"}}
        {{i18n "mute_enhancements.default_users.muted"}}
      </label>
      <UserChooser
        class="mute-enhancements-default-muted-users"
        @onChange={{this.onChangeMuted}}
        @options={{hash excludedUsernames=this.ignored}}
        @value={{this.muted}}
      />

      {{#if this.withGroups}}
        <label>
          {{dIcon "d-muted"}}
          {{i18n "mute_enhancements.default_users.muted_groups"}}
        </label>
        <GroupChooser
          class="mute-enhancements-default-muted-groups"
          @content={{this.mutableGroups}}
          @labelProperty="name"
          @onChange={{this.onChangeMutedGroups}}
          @value={{this.mutedGroupIds}}
        />
      {{/if}}

      <div>
        <DButton
          class="btn-default mute-enhancements-save-default-users"
          @action={{this.save}}
          @disabled={{if this.dirty this.saving true}}
          @label="mute_enhancements.default_users.save"
        />
      </div>
    </div>
  </template>
}
