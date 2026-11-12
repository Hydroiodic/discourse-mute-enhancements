// Preference pages hidden from members of some groups (see HiddenPreferences on the server). The
// tabs are hidden with CSS, in the preferences nav and in the user nav of the sidebar, and the
// routes send the member to Account, so links to them from elsewhere do not open them either.

// Routes of each page. Tags is an older page with the tag part of Tracking.
const ROUTES = {
  tracking: ["tracking", "tags"],
  users: ["users"],
};

export default function setupHiddenPreferences(api) {
  const pages = api.getCurrentUser()?.mute_enhancements_hidden_preferences;
  if (!pages?.length) {
    return;
  }

  for (const page of pages) {
    document.documentElement.classList.add(
      `mute-enhancements-hide-preferences-${page}`
    );

    for (const route of ROUTES[page] ?? []) {
      api.modifyClass(
        `route:preferences.${route}`,
        (Superclass) =>
          class extends Superclass {
            afterModel() {
              this.router.replaceWith("preferences.account");
            }
          }
      );
    }
  }
}
