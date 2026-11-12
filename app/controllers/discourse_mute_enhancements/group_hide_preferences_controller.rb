# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Sets the preference pages hidden from a group's members (HiddenPreferences).
  class GroupHidePreferencesController < GroupSettingsController
    # PUT /mute-enhancements/groups/:group_id/hide-preferences
    #   hidden_pages: comma-separated, from tracking and users; empty for none
    def update
      raise Discourse::InvalidParameters.new(:hidden_pages) if !params.key?(:hidden_pages)

      if HiddenPreferences.update(@group, params[:hidden_pages])
        StaffActionLogger.new(current_user).log_custom(
          "mute_enhancements_group_hide_preferences",
          group: @group.name,
          hidden_pages: HiddenPreferences.group_pages(@group).join(", "),
        )
      end

      render json: { hidden_preferences: HiddenPreferences.group_pages(@group) }
    rescue HiddenPreferences::InvalidPages
      raise Discourse::InvalidParameters.new(:hidden_pages)
    end

    private

    def feature
      HiddenPreferences
    end
  end
end
