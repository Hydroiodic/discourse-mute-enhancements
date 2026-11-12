# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Turns enhanced-ignore's hide_ignored_topics on for a group's members (GroupHideIgnoredTopics).
  class GroupHideIgnoredTopicsController < GroupSettingsController
    # PUT /mute-enhancements/groups/:group_id/hide-ignored-topics
    #   enabled: "true" or "false"
    def update
      enabled = params[:enabled].to_s
      raise Discourse::InvalidParameters.new(:enabled) if %w[true false].exclude?(enabled)

      changed, applied_user_ids = GroupHideIgnoredTopics.update(@group, enabled == "true")
      on = GroupHideIgnoredTopics.on?(@group)

      if changed
        StaffActionLogger.new(current_user).log_custom(
          "mute_enhancements_group_hide_ignored_topics",
          group: @group.name,
          enabled: on,
          applied_user_count: applied_user_ids.size,
        )
      end

      render json: { hide_ignored_topics: on, applied_user_count: applied_user_ids.size }
    end

    private

    def feature
      GroupHideIgnoredTopics
    end
  end
end
