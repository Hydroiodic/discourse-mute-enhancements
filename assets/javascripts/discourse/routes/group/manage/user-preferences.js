import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";
import { hasUserPreferencesPage } from "../../../lib/group-user-preferences";

export default class GroupManageUserPreferences extends DiscourseRoute {
  @service router;

  titleToken() {
    return i18n("mute_enhancements.group_user_preferences.title");
  }

  model() {
    return this.modelFor("group.manage");
  }

  afterModel(group) {
    if (!hasUserPreferencesPage(group)) {
      this.router.replaceWith("group.manage.profile", group);
    }
  }
}
