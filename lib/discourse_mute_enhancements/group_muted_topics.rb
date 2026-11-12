# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Topics muted for a group's members, set by admins on the group's Manage > Member preferences
  # page, one topic id per line:
  #
  # - saving sets the notification level of every current member to Muted for the topics that
  #   were added, whatever it was before;
  # - a user who joins the group gets all of them muted;
  # - members can change the level on the topic like any other; leaving the group, or removing a
  #   topic from the list, leaves it as it is.
  #
  # The levels are set with core's user_changed reason, as if members had muted the topics
  # themselves, so the notification levels of categories and tags do not change them. Only topics
  # (not private messages) that are not deleted can be added. Automatic groups have none.
  #
  # Stored as a comma-separated list of ids in a group custom field, which is deleted when there
  # are none.
  module GroupMutedTopics
    FIELD = "mute_enhancements_muted_topics"
    ID_FORMAT = /\A\d+\z/

    class InvalidTopics < StandardError
    end

    def self.enabled?
      SiteSetting.mute_enhancements_enabled && SiteSetting.mute_enhancements_group_muted_topics
    end

    def self.topic_ids(group)
      GroupCustomField
        .where(group_id: group.id, name: FIELD)
        .pick(:value)
        .to_s
        .split(",")
        .map(&:to_i)
    end

    # Replaces the group's topics with the ids in value, separated by new lines, spaces or commas,
    # and mutes the added ones for current members. Returns whether the list changed and the ids
    # of members whose level changed.
    def self.update(group, value)
      tokens = value.to_s.split(/[\s,]+/).compact_blank
      ids = tokens.grep(ID_FORMAT).map(&:to_i).uniq
      found = Topic.where(id: ids, archetype: Archetype.default).pluck(:id)
      invalid = tokens.grep_v(ID_FORMAT) + (ids - found).map(&:to_s)
      raise InvalidTopics, invalid.uniq.join(", ") if invalid.present?

      saved = topic_ids(group)
      return false, [] if ids == saved

      GroupCustomField.transaction do
        GroupCustomField.where(group_id: group.id, name: FIELD).delete_all
        if ids.present?
          GroupCustomField.create!(group_id: group.id, name: FIELD, value: ids.join(","))
        end
      end
      [true, apply(group, nil, only_topic_ids: ids - saved)]
    end

    # Mutes the group's topics, or only only_topic_ids, for the given members of the group (all
    # members when nil). Returns the ids of members whose level changed.
    def self.apply(group, member_ids, only_topic_ids: nil)
      return [] if !enabled? || group.automatic || member_ids&.empty?
      topic_ids = only_topic_ids || topic_ids(group)
      return [] if topic_ids.empty?

      params = {
        group_id: group.id,
        member_ids:,
        topic_ids:,
        muted: TopicUser.notification_levels[:muted],
        reason: TopicUser.notification_reasons[:user_changed],
        regular: Archetype.default,
        now: Time.zone.now,
      }
      rows = DB.query(<<~SQL, params)
        INSERT INTO topic_users
          (user_id, topic_id, notification_level, notifications_reason_id, notifications_changed_at)
        SELECT gu.user_id, t.id, :muted, :reason, :now
        FROM group_users gu
        JOIN topics t
          ON t.id IN (:topic_ids) AND t.deleted_at IS NULL AND t.archetype = :regular
        WHERE gu.group_id = :group_id
          #{member_ids ? "AND gu.user_id IN (:member_ids)" : ""}
        ON CONFLICT (user_id, topic_id) DO UPDATE
          SET notification_level = EXCLUDED.notification_level,
              notifications_reason_id = EXCLUDED.notifications_reason_id,
              notifications_changed_at = EXCLUDED.notifications_changed_at
          WHERE topic_users.notification_level <> EXCLUDED.notification_level
        RETURNING user_id, topic_id
      SQL

      publish_changes(rows, params)
      rows.map(&:user_id).uniq
    end

    # Tells open topics about the new level, as TopicUser.change does. It does not trigger
    # :topic_notification_level_changed, which is for levels users change themselves.
    def self.publish_changes(rows, params)
      message = {
        notification_level_change: params[:muted],
        notifications_reason_id: params[:reason],
      }
      rows
        .group_by(&:topic_id)
        .each do |topic_id, changed|
          MessageBus.publish("/topic/#{topic_id}", message, user_ids: changed.map(&:user_id))
        end
    end
    private_class_method :publish_changes
  end
end
