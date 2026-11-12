# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Sets the topics muted for a group's members (GroupMutedTopics).
  class GroupMutedTopicsController < GroupSettingsController
    # PUT /mute-enhancements/groups/:group_id/muted-topics
    #   topic_ids: separated by new lines, spaces or commas; empty for none
    def update
      raise Discourse::InvalidParameters.new(:topic_ids) if !params.key?(:topic_ids)

      changed, applied_user_ids = GroupMutedTopics.update(@group, params[:topic_ids])
      topic_ids = GroupMutedTopics.topic_ids(@group)

      if changed
        StaffActionLogger.new(current_user).log_custom(
          "mute_enhancements_group_muted_topics",
          group: @group.name,
          topic_ids: topic_ids.join(", "),
          applied_user_count: applied_user_ids.size,
        )
      end

      render json: { muted_topic_ids: topic_ids, applied_user_count: applied_user_ids.size }
    rescue GroupMutedTopics::InvalidTopics => e
      render_json_error(I18n.t("mute_enhancements.errors.invalid_muted_topics", topics: e.message))
    end

    private

    def feature
      GroupMutedTopics
    end
  end
end
