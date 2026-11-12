// Group > Manage > User preferences, the plugin's page next to Membership. The group show
// serializer only includes its fields for admins and groups that are not automatic, so the page
// exists when any of them is there.
export function hasUserPreferencesPage(group) {
  return (
    group?.mute_enhancements_default_users !== undefined ||
    group?.mute_enhancements_hidden_preferences !== undefined ||
    group?.mute_enhancements_muted_topic_ids !== undefined ||
    group?.mute_enhancements_enhanced_ignore !== undefined
  );
}

// Core has no API for the tabs of a group's Manage page, so the plugin adds its tab after
// Membership (or at the end).
export default function setupGroupUserPreferences(api) {
  api.modifyClass(
    "controller:group.manage",
    (Superclass) =>
      class extends Superclass {
        get tabs() {
          const tabs = [...super.tabs];
          if (hasUserPreferencesPage(this.model)) {
            const membership = tabs.findIndex(
              (tab) => tab.route === "group.manage.membership"
            );
            tabs.splice(membership === -1 ? tabs.length : membership + 1, 0, {
              route: "group.manage.user-preferences",
              title: "mute_enhancements.group_user_preferences.title",
            });
          }
          return tabs;
        }
      }
  );
}
