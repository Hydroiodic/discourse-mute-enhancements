# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Muting or ignoring a group mutes or ignores each of its members, staff excepted. The plugin
  # writes core's own muted_users / ignored_users rows, so everything core does for a muted or
  # ignored user (notifications, personal messages, chat, hidden posts in topics, search) applies
  # to them. DerivedMute marks the rows that came from group mutes; reconcile keeps those in line
  # with the groups' members and never touches rows the user set up themselves:
  #
  # - a member who joins later gets a row, unless the user already has one for them;
  # - a member who leaves, becomes staff, or whose groups are all unmuted loses the row;
  # - a member the user unmuted on their own (the user card, the muted users list) stays unmuted
  #   while the group stays muted;
  # - a member the user also mutes by hand (adds to the muted users list) keeps the row when the
  #   group is unmuted.
  #
  # Muting and ignoring stay separate as in core: a group is either muted or ignored, and a group
  # mute does not add a muted_users row for someone the user already ignores.
  module GroupMutes
    TABLES = {
      mute: {
        table: "muted_users",
        column: "muted_user_id",
      },
      ignore: {
        table: "ignored_users",
        column: "ignored_user_id",
      },
    }.freeze

    PARAMS = {
      mute: :mute_enhancements_muted_group_ids,
      ignore: :mute_enhancements_ignored_group_ids,
    }.freeze

    CONVERTED_PARAM = :mute_enhancements_converted_muted_usernames

    def self.enabled?
      SiteSetting.mute_enhancements_enabled && SiteSetting.mute_enhancements_group_mutes
    end

    def self.serialize_for?(scope, user)
      enabled? && scope.user.present? && (scope.user.id == user.id || scope.is_admin?)
    end

    def self.group_ids(user, level)
      GroupMute.where(user_id: user.id, level: LEVELS[level]).order(:group_id).pluck(:group_id)
    end

    # Groups the user may mute: groups they can see whose members they can see, except automatic
    # groups (trust levels, staff, everyone).
    def self.mutable_groups(user)
      Group.where(automatic: false).visible_groups(user).members_visible_groups(user)
    end

    # What the preferences page offers: the groups above and the ones already muted or ignored.
    def self.choosable_groups(user)
      Group
        .where(id: mutable_groups(user).select(:id))
        .or(Group.where(id: GroupMute.where(user_id: user.id).select(:group_id)))
        .order(:name)
    end

    # Replaces the user's muted or ignored groups for the levels given. New groups must be ones
    # the user may mute; groups already set may always be removed. A group in both lists is
    # ignored. Levels the user is not allowed to use (Guardian#can_mute_users? and
    # #can_ignore_users?) are left as they are.
    def self.update(user, group_ids_by_level)
      guardian = Guardian.new(user)
      allowed =
        {
          mute: guardian.can_mute_users?,
          ignore: guardian.can_ignore_users?,
        }.select { |level, can| can && group_ids_by_level.key?(level) }.keys
      return if allowed.empty?

      current = GroupMute.where(user_id: user.id).pluck(:group_id, :level).to_h
      submitted = group_ids_by_level.slice(*allowed).transform_values { |ids| ids.map(&:to_i).uniq }
      addable = mutable_groups(user).where(id: submitted.values.flatten).pluck(:id).to_set

      desired = {}
      current.each do |group_id, level|
        level_name = LEVELS.key(level)
        desired[group_id] = level if !allowed.include?(level_name)
      end
      %i[mute ignore].each do |level|
        next if !allowed.include?(level)
        submitted[level].each do |group_id|
          next if !addable.include?(group_id) && !current.key?(group_id)
          next if level == :mute && submitted[:ignore]&.include?(group_id)
          desired[group_id] = LEVELS[level]
        end
      end

      return if desired == current

      GroupMute.transaction do
        GroupMute.where(user_id: user.id).where.not(group_id: desired.keys).delete_all
        desired.each do |group_id, level|
          next if current[group_id] == level
          GroupMute.upsert(
            { user_id: user.id, group_id:, level: },
            unique_by: %i[user_id group_id],
            update_only: %i[level],
          )
        end
        reconcile(user_ids: [user.id])
      end
    end

    # users_controller_update_user_params modifier: lets the preferences page save the group
    # lists, and keeps rows from group mutes when it saves the muted users list.
    #
    # The muted users list leaves those rows out (see UserSerializerExtension), and
    # UserUpdater#update_muted_users deletes every muted_users row not in the list it gets. So
    # their usernames are added back here, before the update runs. Usernames the user did put in
    # the list are muted by hand from now on; apply_user_update unmarks them.
    def self.permit_user_params(result, params)
      return result if !enabled?

      PARAMS.each_value do |key|
        next if !params.key?(key)
        value = params[key]
        result[key] = value.is_a?(Array) ? value.join(",") : value.to_s
      end

      if result.key?(:muted_usernames) && (user = User.find_by_username(params[:username]))
        submitted = result[:muted_usernames].to_s.split(",")
        derived = derived_usernames(user, :mute)
        converted = derived.select { |name| submitted.any? { |s| s.casecmp?(name) } }
        result[:muted_usernames] = (submitted + (derived - converted)).join(",")
        result[CONVERTED_PARAM] = converted.join(",") if converted.present?
      end

      result
    end

    # within_user_updater_transaction handler: runs after core saved the muted users list.
    def self.apply_user_update(user, attributes)
      return if !enabled?

      if attributes.key?(CONVERTED_PARAM)
        DerivedMute.where(
          user_id: user.id,
          level: LEVELS[:mute],
          target_user_id:
            User.where(username_lower: attributes[CONVERTED_PARAM].to_s.downcase.split(",")).select(
              :id,
            ),
        ).delete_all
      end

      lists =
        PARAMS.filter_map do |level, key|
          next if !attributes.key?(key)
          [level, attributes[key].to_s.split(",").map(&:strip).select { |id| id.match?(/\A\d+\z/) }]
        end
      update(user, lists.to_h) if lists.present?
    end

    def self.derived_usernames(user, level)
      User
        .where(id: derived_target_ids(user, level))
        .where(id: DB.query_single(<<~SQL, user_id: user.id))
          SELECT #{TABLES[level][:column]} FROM #{TABLES[level][:table]} WHERE user_id = :user_id
        SQL
        .pluck(:username)
    end

    def self.derived_target_ids(user, level)
      DerivedMute.where(user_id: user.id, level: LEVELS[level]).select(:target_user_id)
    end

    # A member joined or left a group: update the users who muted or ignored that group.
    def self.member_changed(group, member)
      return if !enabled? || group.automatic
      user_ids = GroupMute.where(group_id: group.id).distinct.pluck(:user_id)
      reconcile(user_ids:, target_ids: [member.id]) if user_ids.present?
    end

    def self.group_destroyed(group_id)
      user_ids = GroupMute.where(group_id:).distinct.pluck(:user_id)
      GroupMute.where(group_id:).delete_all
      reconcile(user_ids:) if user_ids.present?
    end

    # Brings muted_users / ignored_users in line with group mutes, for the given users (the ones
    # who muted) and members, or for everyone when both are nil. Ignores go first so that a mute
    # is not added for someone the same user ignores through another group.
    def self.reconcile(user_ids: nil, target_ids: nil)
      %i[ignore mute].each { |level| reconcile_level(level, user_ids:, target_ids:) }
    end

    def self.reconcile_level(level, user_ids:, target_ids:)
      table = TABLES[level][:table]
      column = TABLES[level][:column]
      params = {
        level: LEVELS[level],
        user_ids:,
        target_ids:,
        now: Time.zone.now,
        forever: DiscourseMuteEnhancements.forever,
      }

      covered = +<<~SQL
        SELECT DISTINCT gm.user_id, gu.user_id AS target_user_id
        FROM mute_enhancements_group_mutes gm
        JOIN groups g ON g.id = gm.group_id AND NOT g.automatic
        JOIN group_users gu ON gu.group_id = gm.group_id
        JOIN users u ON u.id = gu.user_id
        WHERE gm.level = :level
          AND gu.user_id <> gm.user_id
          AND NOT u.admin
          AND NOT u.moderator
      SQL
      covered << "AND gm.user_id IN (:user_ids)\n" if user_ids
      covered << "AND gu.user_id IN (:target_ids)\n" if target_ids

      derived_scope = +"d.level = :level"
      derived_scope << " AND d.user_id IN (:user_ids)" if user_ids
      derived_scope << " AND d.target_user_id IN (:target_ids)" if target_ids

      # Rows no group mute covers any more: remove the marker and the row.
      DB.exec(<<~SQL, params)
        WITH covered AS (#{covered}),
        stale AS (
          DELETE FROM mute_enhancements_derived_mutes d
          WHERE #{derived_scope}
            AND NOT EXISTS (
              SELECT 1 FROM covered c
              WHERE c.user_id = d.user_id AND c.target_user_id = d.target_user_id
            )
          RETURNING d.user_id, d.target_user_id
        )
        DELETE FROM #{table} t
        USING stale s
        WHERE t.user_id = s.user_id AND t.#{column} = s.target_user_id
      SQL

      # Covered members without a marker get one and a row, unless the user already has a row of
      # their own for them (or, for mutes, ignores them).
      skip_ignored = <<~SQL if level == :mute
        AND NOT EXISTS (
          SELECT 1 FROM ignored_users i
          WHERE i.user_id = c.user_id AND i.ignored_user_id = c.target_user_id
        )
      SQL

      extra_columns, extra_values =
        level == :ignore ? ["expiring_at, summarized_at,", ":forever, :now,"] : ["", ""]

      # summarized_at is set so that Jobs::IgnoredUsersSummary, which tells moderators when
      # someone is ignored by many users, does not count ignores that come from groups.
      DB.exec(<<~SQL, params)
        WITH covered AS (#{covered}),
        fresh AS (
          INSERT INTO mute_enhancements_derived_mutes (user_id, target_user_id, level, created_at)
          SELECT c.user_id, c.target_user_id, :level, :now
          FROM covered c
          WHERE NOT EXISTS (
              SELECT 1 FROM mute_enhancements_derived_mutes d
              WHERE d.user_id = c.user_id AND d.target_user_id = c.target_user_id AND d.level = :level
            )
            AND NOT EXISTS (
              SELECT 1 FROM #{table} t
              WHERE t.user_id = c.user_id AND t.#{column} = c.target_user_id
            )
            #{skip_ignored}
          ON CONFLICT DO NOTHING
          RETURNING user_id, target_user_id
        )
        INSERT INTO #{table} (user_id, #{column}, #{extra_columns} created_at, updated_at)
        SELECT user_id, target_user_id, #{extra_values} :now, :now
        FROM fresh
        ON CONFLICT DO NOTHING
      SQL
    end

    # Daily clean-up for what the events miss: members who became staff, and group mutes of
    # deleted users or of groups that are gone.
    def self.reconcile_all
      return if !enabled?

      DB.exec(<<~SQL)
        DELETE FROM mute_enhancements_group_mutes gm
        WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = gm.user_id)
           OR NOT EXISTS (SELECT 1 FROM groups g WHERE g.id = gm.group_id AND NOT g.automatic)
      SQL
      reconcile
    end
  end
end
