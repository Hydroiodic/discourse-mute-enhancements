# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Turns HiddenPreferences on or off for a group.
  class GroupHidePreferencesController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_admin

    # PUT /mute-enhancements/groups/:group_id/hide-preferences
    #   enabled: "true" or "false"
    def update
      raise Discourse::NotFound if !HiddenPreferences.enabled?

      group = Group.find(params.require(:group_id))
      raise Discourse::InvalidParameters.new(:group_id) if group.automatic
      enabled = params.require(:enabled).to_s == "true"

      if HiddenPreferences.update(group, enabled)
        StaffActionLogger.new(current_user).log_custom(
          "mute_enhancements_group_hide_preferences",
          group: group.name,
          hide_preferences: enabled,
        )
      end

      render json: { hide_preferences: enabled }
    end
  end
end
