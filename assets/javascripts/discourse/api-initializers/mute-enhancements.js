import { apiInitializer } from "discourse/lib/api";
import setupSearchSuggestions from "../lib/search-suggestions";

export default apiInitializer((api) => {
  setupSearchSuggestions(api);

  // Saved by the Save button of preferences → Users. Both are comma-separated group ids; the
  // server only accepts them when group mutes are enabled.
  api.addSaveableUserField("mute_enhancements_muted_group_ids", {
    page: "users",
  });
  api.addSaveableUserField("mute_enhancements_ignored_group_ids", {
    page: "users",
  });
});
