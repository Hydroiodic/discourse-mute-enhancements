# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Users that a group's members mute or ignore by default, set by admins on the group's
  # Manage > Member preferences page. Works like core's default category and tag notification
  # levels for a group:
  #
  # - a user who joins the group gets a muted_users / ignored_users row of their own for each
  #   default user, unless they already have one for that user (muted or ignored); they can
  #   remove it like any other;
  # - leaving the group, or removing a default, leaves the rows in place;
  # - when a default is added, admins choose whether current members get it too.
  #
  # Staff cannot be muted or ignored in core, so they cannot be defaults. Automatic groups have no
  # defaults, as their members are not added by hand.
  #
  # Kept in a group custom field, user id => level (see GroupLevels).
  module GroupDefaultUsers
    FIELD = "mute_enhancements_default_users"

    class InvalidUsers < StandardError
    end

    def self.enabled?
      SiteSetting.mute_enhancements_enabled && SiteSetting.mute_enhancements_group_default_users
    end

    # The group's defaults, user id => level.
    def self.levels(group)
      GroupLevels.read(group.id, FIELD)
    end

    def self.usernames(group)
      levels = levels(group)
      rows = User.where(id: levels.keys).order(:username_lower).pluck(:id, :username)
      LEVELS.to_h do |level, value|
        [
          :"#{level == :mute ? "muted" : "ignored"}_usernames",
          rows.filter_map { |id, name| name if levels[id] == value },
        ]
      end
    end

    # Replaces the group's defaults. Returns the ids of current members who got a new row (none
    # unless update_existing_users).
    def self.update(group, muted_usernames:, ignored_usernames:, update_existing_users:)
      ignored = find_users(ignored_usernames)
      muted = find_users(muted_usernames) - ignored

      staff = (muted + ignored).select(&:staff?)
      raise InvalidUsers, staff.map(&:username).join(", ") if staff.present?

      desired =
        muted.to_h { |u| [u.id, LEVELS[:mute]] }.merge(ignored.to_h { |u| [u.id, LEVELS[:ignore]] })
      current = levels(group)
      changed = desired.reject { |user_id, level| current[user_id] == level }
      GroupLevels.write(group.id, FIELD, desired) if desired != current

      return [] if !update_existing_users || changed.empty?
      apply(group, nil, only_target_ids: changed.keys)
    end

    # Gives the given members of the group (all members when nil) the group's defaults, or only
    # the defaults for only_target_ids. Returns the ids of members who got a new row.
    def self.apply(group, member_ids, only_target_ids: nil)
      return [] if !enabled? || group.automatic || member_ids&.empty?

      defaults = levels(group)
      defaults = defaults.slice(*only_target_ids) if only_target_ids
      return [] if defaults.empty?

      params = {
        group_id: group.id,
        member_ids:,
        defaults: defaults.to_json,
        now: Time.zone.now,
        forever: DiscourseMuteEnhancements.forever,
      }
      pairs = <<~SQL
        SELECT m.id AS user_id, d.target_user_id, d.level
        FROM (
          SELECT e.key::int AS target_user_id, e.value::int AS level
          FROM jsonb_each_text(CAST(:defaults AS jsonb)) e
        ) d
        JOIN users t ON t.id = d.target_user_id AND NOT t.admin AND NOT t.moderator
        JOIN group_users gu ON gu.group_id = :group_id
          #{member_ids ? "AND gu.user_id IN (:member_ids)" : ""}
        JOIN users m ON m.id = gu.user_id AND m.id <> d.target_user_id
        WHERE NOT EXISTS (
            SELECT 1 FROM muted_users mu
            WHERE mu.user_id = m.id AND mu.muted_user_id = d.target_user_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM ignored_users iu
            WHERE iu.user_id = m.id AND iu.ignored_user_id = d.target_user_id
          )
      SQL

      # summarized_at keeps these ignores out of Jobs::IgnoredUsersSummary's count, which would
      # otherwise tell moderators the default users are ignored by many users.
      DB.query_single(<<~SQL, params.merge(mute: LEVELS[:mute], ignore: LEVELS[:ignore]))
        WITH pairs AS (#{pairs}),
        muted AS (
          INSERT INTO muted_users (user_id, muted_user_id, created_at, updated_at)
          SELECT user_id, target_user_id, :now, :now FROM pairs WHERE level = :mute
          ON CONFLICT DO NOTHING
          RETURNING user_id
        ),
        ignored AS (
          INSERT INTO ignored_users
            (user_id, ignored_user_id, expiring_at, summarized_at, created_at, updated_at)
          SELECT user_id, target_user_id, :forever, :now, :now, :now
          FROM pairs
          WHERE level = :ignore
          ON CONFLICT DO NOTHING
          RETURNING user_id
        )
        SELECT user_id FROM muted UNION SELECT user_id FROM ignored
      SQL
    end

    def self.group_destroyed(group_id)
      GroupCustomField.where(group_id:, name: FIELD).delete_all
    end

    def self.find_users(usernames)
      names =
        Array(usernames)
          .flat_map { |name| name.to_s.split(",") }
          .map { |name| User.normalize_username(name.strip) }
          .compact_blank
      return [] if names.empty?
      User.where(username_lower: names.uniq).to_a
    end
    private_class_method :find_users
  end
end
