# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Users that a group's members mute or ignore by default, set by admins on the group's
  # Membership page. Works like core's default category and tag notification levels for a group:
  #
  # - a user who joins the group gets a muted_users / ignored_users row of their own for each
  #   default user, unless they already have one for that user (muted or ignored); they can
  #   remove it like any other;
  # - leaving the group, or removing a default, leaves the rows in place;
  # - when a default is added, admins choose whether current members get it too.
  #
  # Staff cannot be muted or ignored in core, so they cannot be defaults. Automatic groups have no
  # defaults, as they have no Membership page.
  module GroupDefaultUsers
    class InvalidUsers < StandardError
    end

    def self.enabled?
      SiteSetting.mute_enhancements_enabled && SiteSetting.mute_enhancements_group_default_users
    end

    def self.usernames(group)
      rows =
        GroupDefaultUser
          .where(group_id: group.id)
          .joins(:target_user)
          .order("users.username_lower")
          .pluck(:level, "users.username")
      LEVELS.to_h do |level, value|
        [
          :"#{level == :mute ? "muted" : "ignored"}_usernames",
          rows.filter_map { |l, name| name if l == value },
        ]
      end
    end

    # Replaces the group's defaults. Returns the number of current members the new defaults were
    # applied to (0 unless update_existing_users).
    def self.update(group, muted_usernames:, ignored_usernames:, update_existing_users:)
      ignored = find_users(ignored_usernames)
      muted = find_users(muted_usernames) - ignored

      staff = (muted + ignored).select(&:staff?)
      raise InvalidUsers, staff.map(&:username).join(", ") if staff.present?

      desired =
        muted.to_h { |u| [u.id, LEVELS[:mute]] }.merge(ignored.to_h { |u| [u.id, LEVELS[:ignore]] })
      current = GroupDefaultUser.where(group_id: group.id).pluck(:target_user_id, :level).to_h
      changed = desired.reject { |user_id, level| current[user_id] == level }

      GroupDefaultUser.transaction do
        GroupDefaultUser
          .where(group_id: group.id)
          .where.not(target_user_id: desired.keys)
          .delete_all
        changed.each do |target_user_id, level|
          GroupDefaultUser.upsert(
            { group_id: group.id, target_user_id:, level: },
            unique_by: %i[group_id target_user_id],
            update_only: %i[level],
          )
        end
      end

      return 0 if !update_existing_users || changed.empty?
      apply(group, nil, only_target_ids: changed.keys)
    end

    # Gives the given members of the group (all members when nil) the group's defaults, or only
    # the defaults for only_target_ids. Returns how many members got a new row.
    def self.apply(group, member_ids, only_target_ids: nil)
      return 0 if !enabled? || group.automatic || member_ids&.empty?

      targets = GroupDefaultUser.where(group_id: group.id)
      targets = targets.where(target_user_id: only_target_ids) if only_target_ids
      return 0 if !targets.exists?

      params = {
        group_id: group.id,
        member_ids:,
        target_ids: only_target_ids,
        now: Time.zone.now,
        forever: DiscourseMuteEnhancements.forever,
      }
      pairs = <<~SQL
        SELECT m.id AS user_id, d.target_user_id, d.level
        FROM mute_enhancements_group_default_users d
        JOIN users t ON t.id = d.target_user_id AND NOT t.admin AND NOT t.moderator
        JOIN group_users gu ON gu.group_id = d.group_id
          #{member_ids ? "AND gu.user_id IN (:member_ids)" : ""}
        JOIN users m ON m.id = gu.user_id AND m.id <> d.target_user_id
        WHERE d.group_id = :group_id
          #{only_target_ids ? "AND d.target_user_id IN (:target_ids)" : ""}
          AND NOT EXISTS (
            SELECT 1 FROM muted_users mu WHERE mu.user_id = m.id AND mu.muted_user_id = d.target_user_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM ignored_users iu WHERE iu.user_id = m.id AND iu.ignored_user_id = d.target_user_id
          )
      SQL

      # summarized_at keeps these ignores out of Jobs::IgnoredUsersSummary's count, which would
      # otherwise tell moderators the default users are ignored by many users.
      DB.query_single(<<~SQL, params.merge(mute: LEVELS[:mute], ignore: LEVELS[:ignore])).first.to_i
        WITH pairs AS (#{pairs}),
        muted AS (
          INSERT INTO muted_users (user_id, muted_user_id, created_at, updated_at)
          SELECT user_id, target_user_id, :now, :now FROM pairs WHERE level = :mute
          ON CONFLICT DO NOTHING
          RETURNING user_id
        ),
        ignored AS (
          INSERT INTO ignored_users (user_id, ignored_user_id, expiring_at, summarized_at, created_at, updated_at)
          SELECT user_id, target_user_id, :forever, :now, :now, :now FROM pairs WHERE level = :ignore
          ON CONFLICT DO NOTHING
          RETURNING user_id
        )
        SELECT COUNT(DISTINCT user_id) FROM (SELECT user_id FROM muted UNION ALL SELECT user_id FROM ignored) x
      SQL
    end

    def self.find_users(usernames)
      names =
        Array(usernames)
          .flat_map { |n| n.to_s.split(",") }
          .map { |n| User.normalize_username(n.strip) }
          .reject(&:blank?)
      return [] if names.empty?
      User.where(username_lower: names.uniq).to_a
    end
  end
end
