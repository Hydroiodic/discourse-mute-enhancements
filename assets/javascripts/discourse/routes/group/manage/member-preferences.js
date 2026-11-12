import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";
import { hasMemberPreferencesPage } from "../../../lib/group-member-preferences";

export default class GroupManageMemberPreferences extends DiscourseRoute {
  @service router;

  titleToken() {
    return i18n("mute_enhancements.group_member_preferences.title");
  }

  model() {
    return this.modelFor("group.manage");
  }

  afterModel(group) {
    if (!hasMemberPreferencesPage(group)) {
      this.router.replaceWith("group.manage.profile", group);
    }
  }
}
