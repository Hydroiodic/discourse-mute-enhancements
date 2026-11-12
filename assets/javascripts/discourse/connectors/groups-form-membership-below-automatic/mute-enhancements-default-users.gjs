import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import GroupDefaultNotificationsModal from "discourse/components/modal/group-default-notifications";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import UserChooser from "discourse/select-kit/components/user-chooser";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// Group → Manage → Membership (admins only): users that members of the group mute or ignore by
// default. Has its own Save button, as the page's Save button only saves core's fields.
export default class MuteEnhancementsDefaultUsers extends Component {
  static shouldRender(args) {
    return (
      !!args.model?.id &&
      args.model.mute_enhancements_default_users !== undefined
    );
  }

  @service modal;
  @service toasts;

  @tracked muted = [...this.saved.muted_usernames];
  @tracked ignored = [...this.saved.ignored_usernames];
  @tracked saving = false;

  get group() {
    return this.args.outletArgs.model;
  }

  get saved() {
    return this.group.mute_enhancements_default_users;
  }

  get dirty() {
    return (
      this.muted.join(",") !== this.saved.muted_usernames.join(",") ||
      this.ignored.join(",") !== this.saved.ignored_usernames.join(",")
    );
  }

  // Defaults that are new or moved between muted and ignored; only these can be given to
  // current members.
  get addedCount() {
    return (
      this.muted.filter((name) => !this.saved.muted_usernames.includes(name))
        .length +
      this.ignored.filter(
        (name) => !this.saved.ignored_usernames.includes(name)
      ).length
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

    this.saving = true;
    try {
      const result = await ajax(
        `/mute-enhancements/groups/${this.group.id}/default-users`,
        {
          type: "PUT",
          data: {
            muted_usernames: this.muted.join(","),
            ignored_usernames: this.ignored.join(","),
            update_existing_users: updateExistingUsers,
          },
        }
      );

      this.group.set("mute_enhancements_default_users", {
        muted_usernames: result.muted_usernames,
        ignored_usernames: result.ignored_usernames,
      });
      this.muted = [...result.muted_usernames];
      this.ignored = [...result.ignored_usernames];

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
        {{i18n "mute_enhancements.default_users.title"}}
      </label>
      <div class="control-instructions">
        {{i18n "mute_enhancements.default_users.description"}}
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

      <DButton
        class="btn-default mute-enhancements-save-default-users"
        @action={{this.save}}
        @disabled={{if this.dirty this.saving true}}
        @label="mute_enhancements.default_users.save"
      />
    </div>
  </template>
}
