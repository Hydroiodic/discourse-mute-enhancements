import { apiInitializer } from "discourse/lib/api";
import setupGroupMemberPreferences from "../lib/group-member-preferences";
import setupHiddenPreferences from "../lib/hidden-preferences";
import setupSearchSuggestions from "../lib/search-suggestions";

export default apiInitializer((api) => {
  setupSearchSuggestions(api);
  setupHiddenPreferences(api);
  setupGroupMemberPreferences(api);

  // Saved by the Save button of Preferences > Users. Both are comma-separated group ids; the
  // server only accepts them when group mutes are enabled.
  api.addSaveableUserField("mute_enhancements_muted_group_ids", {
    page: "users",
  });
  api.addSaveableUserField("mute_enhancements_ignored_group_ids", {
    page: "users",
  });
});
