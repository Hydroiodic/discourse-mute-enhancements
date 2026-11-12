# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Sets the preference pages hidden from a group's members (HiddenPreferences).
  class GroupHidePreferencesController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_admin

    # PUT /mute-enhancements/groups/:group_id/hide-preferences
    #   hidden_pages: comma-separated, from tracking and users; empty for none
    def update
      raise Discourse::NotFound if !HiddenPreferences.enabled?

      group = Group.find(params.require(:group_id))
      raise Discourse::InvalidParameters.new(:group_id) if group.automatic
      raise Discourse::InvalidParameters.new(:hidden_pages) if !params.key?(:hidden_pages)

      if HiddenPreferences.update(group, params[:hidden_pages])
        StaffActionLogger.new(current_user).log_custom(
          "mute_enhancements_group_hide_preferences",
          group: group.name,
          hidden_pages: HiddenPreferences.group_pages(group).join(", "),
        )
      end

      render json: { hidden_preferences: HiddenPreferences.group_pages(group) }
    rescue HiddenPreferences::InvalidPages
      raise Discourse::InvalidParameters.new(:hidden_pages)
    end
  end
end
