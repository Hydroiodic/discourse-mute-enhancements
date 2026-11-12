# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Turns on the enhanced-ignore plugin's preference that hides topics started by ignored users
  # from topic lists (the hide_ignored_topics user custom field) for a group's members, chosen by
  # admins on the group's Manage > User preferences page:
  #
  # - turning it on sets the preference for every current member;
  # - a user who joins the group while it is on gets it set too;
  # - members can still turn the preference off in Preferences > Notifications; turning the group
  #   setting off, or leaving the group, leaves it as it is.
  #
  # enhanced-ignore owns the preference and the topic list filter, so the setting is only there
  # while that plugin is installed and enabled. Automatic groups do not have it.
  #
  # Stored as a group custom field that exists only while the setting is on.
  module GroupHideIgnoredTopics
    FIELD = "mute_enhancements_hide_ignored_topics"
    USER_FIELD = "hide_ignored_topics"

    def self.enabled?
      SiteSetting.mute_enhancements_enabled &&
        SiteSetting.mute_enhancements_group_hide_ignored_topics && enhanced_ignore_enabled?
    end

    def self.enhanced_ignore_enabled?
      SiteSetting.respond_to?(:enhanced_ignore_enabled) && SiteSetting.enhanced_ignore_enabled
    end

    def self.on?(group)
      GroupCustomField.exists?(group_id: group.id, name: FIELD)
    end

    # Turns the setting on or off. Returns whether it changed and the ids of members whose
    # preference was turned on.
    def self.update(group, on)
      return false, [] if on == on?(group)

      if on
        GroupCustomField.create!(group_id: group.id, name: FIELD, value: "t")
        [true, apply(group, nil)]
      else
        GroupCustomField.where(group_id: group.id, name: FIELD).delete_all
        [true, []]
      end
    end

    # Turns the preference on for the given members of the group (all members when nil) if the
    # group has the setting on. Returns the ids of members whose preference changed.
    def self.apply(group, member_ids)
      return [] if !enabled? || group.automatic || member_ids&.empty? || !on?(group)

      params = {
        group_id: group.id,
        member_ids:,
        name: USER_FIELD,
        true_values: HasCustomFields::Helpers::CUSTOM_FIELD_TRUE,
        now: Time.zone.now,
      }
      members = <<~SQL
        SELECT user_id FROM group_users
        WHERE group_id = :group_id #{member_ids ? "AND user_id IN (:member_ids)" : ""}
      SQL

      # user_custom_fields has no unique index on (user_id, name), so existing rows are updated
      # and missing ones inserted.
      ActiveRecord::Base.transaction do
        updated = DB.query_single(<<~SQL, params)
          UPDATE user_custom_fields
          SET value = 't', updated_at = :now
          WHERE name = :name AND value NOT IN (:true_values) AND user_id IN (#{members})
          RETURNING user_id
        SQL

        inserted = DB.query_single(<<~SQL, params)
          INSERT INTO user_custom_fields (user_id, name, value, created_at, updated_at)
          SELECT m.user_id, :name, 't', :now, :now
          FROM (#{members}) m
          WHERE NOT EXISTS (
            SELECT 1 FROM user_custom_fields ucf WHERE ucf.user_id = m.user_id AND ucf.name = :name
          )
          RETURNING user_id
        SQL

        (updated + inserted).uniq
      end
    end
  end
end
