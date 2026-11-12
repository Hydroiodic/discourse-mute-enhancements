# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Turns on the enhanced-ignore plugin's preferences for a group's members, chosen by admins on
  # the group's Manage > Member preferences page, each on its own (none by default):
  #
  # - hide_ignored_topics: topics started by ignored users are left out of the member's topic
  #   lists;
  # - ignored_user_cannot_reply_to_me: ignored users cannot reply to the member's topics.
  #
  # Turning an option on sets the preference for every current member, and a user who joins the
  # group gets all of the group's options set. Members can still turn them off in
  # Preferences > Notifications; turning an option off, or leaving the group, leaves them as they
  # are.
  #
  # enhanced-ignore owns the preferences (user custom fields with the same names), so the setting
  # is only there while that plugin is installed and enabled. Automatic groups do not have it.
  #
  # Stored as a comma-separated list in a group custom field, which is deleted when none are on.
  module GroupEnhancedIgnore
    FIELD = "mute_enhancements_enhanced_ignore"
    OPTIONS = %w[hide_ignored_topics ignored_user_cannot_reply_to_me].freeze

    class InvalidOptions < StandardError
    end

    def self.enabled?
      SiteSetting.mute_enhancements_enabled &&
        SiteSetting.mute_enhancements_group_enhanced_ignore && enhanced_ignore_enabled?
    end

    def self.enhanced_ignore_enabled?
      SiteSetting.respond_to?(:enhanced_ignore_enabled) && SiteSetting.enhanced_ignore_enabled
    end

    def self.group_options(group)
      OPTIONS & GroupCustomField.where(group_id: group.id, name: FIELD).pick(:value).to_s.split(",")
    end

    # Replaces the group's options with those in value, comma-separated, and turns the added ones
    # on for current members. Returns whether the options changed and the ids of members whose
    # preferences changed.
    def self.update(group, value)
      given = value.to_s.split(",").map(&:strip).compact_blank
      raise InvalidOptions, (given - OPTIONS).join(", ") if (given - OPTIONS).present?

      options = OPTIONS & given
      saved = group_options(group)
      return false, [] if options == saved

      GroupCustomField.transaction do
        GroupCustomField.where(group_id: group.id, name: FIELD).delete_all
        if options.present?
          GroupCustomField.create!(group_id: group.id, name: FIELD, value: options.join(","))
        end
      end
      [true, apply(group, nil, only_options: options - saved)]
    end

    # Turns the group's options, or only only_options, on for the given members of the group (all
    # members when nil). Returns the ids of members whose preferences changed.
    def self.apply(group, member_ids, only_options: nil)
      return [] if !enabled? || group.automatic || member_ids&.empty?
      options = only_options || group_options(group)
      return [] if options.empty?

      params = {
        group_id: group.id,
        member_ids:,
        true_values: HasCustomFields::Helpers::CUSTOM_FIELD_TRUE,
        now: Time.zone.now,
      }
      members = <<~SQL
        SELECT user_id FROM group_users
        WHERE group_id = :group_id #{member_ids ? "AND user_id IN (:member_ids)" : ""}
      SQL

      ActiveRecord::Base.transaction do
        options.flat_map { |name| turn_on(name, members, params.merge(name:)) }.uniq
      end
    end

    # user_custom_fields has no unique index on (user_id, name), so existing rows are updated and
    # missing ones inserted. Returns the ids of users whose preference changed.
    def self.turn_on(name, members, params)
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

      updated + inserted
    end
    private_class_method :turn_on
  end
end
