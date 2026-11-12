# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Sets the enhanced-ignore options turned on for a group's members (GroupEnhancedIgnore).
  class GroupEnhancedIgnoreController < GroupSettingsController
    # PUT /mute-enhancements/groups/:group_id/enhanced-ignore
    #   options: comma-separated, from hide_ignored_topics and ignored_user_cannot_reply_to_me;
    #     empty for none
    def update
      raise Discourse::InvalidParameters.new(:options) if !params.key?(:options)

      changed, applied_user_ids = GroupEnhancedIgnore.update(@group, params[:options])
      options = GroupEnhancedIgnore.group_options(@group)

      if changed
        StaffActionLogger.new(current_user).log_custom(
          "mute_enhancements_group_enhanced_ignore",
          group: @group.name,
          options: options.join(", "),
          applied_user_count: applied_user_ids.size,
        )
      end

      render json: { enhanced_ignore: options, applied_user_count: applied_user_ids.size }
    rescue GroupEnhancedIgnore::InvalidOptions
      raise Discourse::InvalidParameters.new(:options)
    end

    private

    def feature
      GroupEnhancedIgnore
    end
  end
end
