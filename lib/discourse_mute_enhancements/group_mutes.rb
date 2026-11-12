# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Muting or ignoring a group mutes or ignores each of its members, staff excepted. The plugin
  # writes core's own muted_users / ignored_users rows, so everything core does for a muted or
  # ignored user (notifications, personal messages, chat, hidden posts in topics, search) applies
  # to them. The rows that came from group mutes are marked (UserStore's derived_mutes and
  # derived_ignores); reconcile keeps those in line with the groups' members and never touches
  # rows the user set up themselves:
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
  #
  # The groups are kept in UserStore's group_mutes, group id => level. A marker stays when its row
  # is deleted, e.g. when the user unmutes that one member from the user card, so the group mute
  # does not bring the row back.
  module GroupMutes
    TABLES = {
      mute: {
        table: "muted_users",
        column: "muted_user_id",
        markers: "derived_mutes",
      },
      ignore: {
        table: "ignored_users",
        column: "ignored_user_id",
        markers: "derived_ignores",
      },
    }.freeze

    STORE = "group_mutes"

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

    # The groups the user muted or ignored, group id => level.
    def self.levels(user)
      UserStore.read(STORE, user.id)
    end

    def self.group_ids(user, level)
      levels(user).filter_map { |group_id, l| group_id if l == LEVELS[level] }.sort
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
        .or(Group.where(id: levels(user).keys))
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

      current = levels(user)
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

      # Only the difference is written, so a group mute added meanwhile (GroupDefaultGroups) stays.
      ActiveRecord::Base.transaction do
        UserStore.change(
          STORE,
          user.id,
          set: desired.reject { |group_id, level| current[group_id] == level },
          remove: current.keys - desired.keys,
        )
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
        usernames = attributes[CONVERTED_PARAM].to_s.downcase.split(",")
        UserStore.remove(
          TABLES[:mute][:markers],
          { user.id => User.where(username_lower: usernames).pluck(:id) },
        )
      end

      lists =
        PARAMS.filter_map do |level, key|
          next if !attributes.key?(key)
          [level, attributes[key].to_s.split(",").map(&:strip).grep(/\A\d+\z/)]
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
    private_class_method :derived_usernames

    # The members whose muted_users / ignored_users row came from group mutes.
    def self.derived_target_ids(user, level)
      UserStore.read(TABLES[level][:markers], user.id).keys
    end

    # A member joined or left a group: update the users who muted or ignored that group.
    def self.member_changed(group, member)
      return if !enabled? || group.automatic
      user_ids = UserStore.user_ids_with(STORE, group.id)
      reconcile(user_ids:, target_ids: [member.id]) if user_ids.present?
    end

    def self.group_destroyed(group_id)
      user_ids = UserStore.remove_everywhere(STORE, group_id)
      reconcile(user_ids:) if user_ids.present?
    end

    # Brings muted_users / ignored_users in line with group mutes, for the given users (the ones
    # who muted) and members, or for everyone when both are nil. Ignores go first so that a mute
    # is not added for someone the same user ignores through another group.
    def self.reconcile(user_ids: nil, target_ids: nil)
      ActiveRecord::Base.transaction do
        %i[ignore mute].each { |level| reconcile_level(level, user_ids:, target_ids:) }
      end
    end

    def self.reconcile_level(level, user_ids:, target_ids:)
      table = TABLES[level][:table]
      column = TABLES[level][:column]
      markers = TABLES[level][:markers]
      only_listed = !user_ids.nil?
      params = {
        level: LEVELS[level],
        target_ids:,
        **UserStore.sql_params([STORE, markers], user_ids),
      }

      covered = +<<~SQL
        SELECT DISTINCT gm.user_id, gu.user_id AS target_user_id
        FROM (#{UserStore.entries_sql(STORE, only_listed:)}) gm
        JOIN groups g ON g.id = gm.item_id AND NOT g.automatic
        JOIN group_users gu ON gu.group_id = gm.item_id
        JOIN users u ON u.id = gu.user_id
        WHERE gm.value = :level
          AND gu.user_id <> gm.user_id
          AND NOT u.admin
          AND NOT u.moderator
      SQL
      covered << "AND gu.user_id IN (:target_ids)\n" if target_ids

      marked = +<<~SQL
        SELECT m.user_id, m.item_id AS target_user_id
        FROM (#{UserStore.entries_sql(markers, only_listed:)}) m
      SQL
      marked << "WHERE m.item_id IN (:target_ids)\n" if target_ids

      # Marked rows no group mute covers any more: remove the marker and the row.
      stale = DB.query(<<~SQL, params)
        WITH covered AS (#{covered}), marked AS (#{marked})
        SELECT m.user_id, m.target_user_id
        FROM marked m
        WHERE NOT EXISTS (
          SELECT 1 FROM covered c
          WHERE c.user_id = m.user_id AND c.target_user_id = m.target_user_id
        )
      SQL
      if stale.present?
        UserStore.remove(
          markers,
          stale.group_by(&:user_id).transform_values { |rows| rows.map(&:target_user_id) },
        )
        DB.exec(<<~SQL, pairs_params(stale))
          DELETE FROM #{table} t
          USING unnest(
            string_to_array(:pair_user_ids, ',')::int[],
            string_to_array(:pair_target_ids, ',')::int[]
          ) AS s(user_id, target_user_id)
          WHERE t.user_id = s.user_id AND t.#{column} = s.target_user_id
        SQL
      end

      # Covered members without a marker get one and a row, unless the user already has a row of
      # their own for them (or, for mutes, ignores them).
      skip_ignored = <<~SQL if level == :mute
        AND NOT EXISTS (
          SELECT 1 FROM ignored_users i
          WHERE i.user_id = c.user_id AND i.ignored_user_id = c.target_user_id
        )
      SQL
      fresh = DB.query(<<~SQL, params)
        WITH covered AS (#{covered}), marked AS (#{marked})
        SELECT c.user_id, c.target_user_id
        FROM covered c
        WHERE NOT EXISTS (
            SELECT 1 FROM marked m
            WHERE m.user_id = c.user_id AND m.target_user_id = c.target_user_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM #{table} t
            WHERE t.user_id = c.user_id AND t.#{column} = c.target_user_id
          )
          #{skip_ignored}
      SQL
      return if fresh.empty?

      UserStore.merge(
        markers,
        fresh
          .group_by(&:user_id)
          .transform_values { |rows| rows.to_h { |row| [row.target_user_id, 1] } },
      )

      extra_columns, extra_values =
        level == :ignore ? ["expiring_at, summarized_at,", ":forever, :now,"] : ["", ""]

      # summarized_at is set so that Jobs::IgnoredUsersSummary, which tells moderators when
      # someone is ignored by many users, does not count ignores that come from groups.
      DB.exec(
        <<~SQL,
          INSERT INTO #{table} (user_id, #{column}, #{extra_columns} created_at, updated_at)
          SELECT s.user_id, s.target_user_id, #{extra_values} :now, :now
          FROM unnest(
            string_to_array(:pair_user_ids, ',')::int[],
            string_to_array(:pair_target_ids, ',')::int[]
          ) AS s(user_id, target_user_id)
          ON CONFLICT DO NOTHING
        SQL
        **pairs_params(fresh),
        now: Time.zone.now,
        forever: DiscourseMuteEnhancements.forever,
      )
    end
    private_class_method :reconcile_level

    def self.pairs_params(rows)
      {
        pair_user_ids: rows.map(&:user_id).join(","),
        pair_target_ids: rows.map(&:target_user_id).join(","),
      }
    end
    private_class_method :pairs_params

    # Daily clean-up for what the events miss: members who became staff, and group mutes of
    # deleted users or of groups that are gone.
    def self.reconcile_all
      return if !enabled?

      UserStore.delete_deleted_users
      UserStore.remove_missing(STORE, "SELECT id FROM groups WHERE NOT automatic")
      reconcile
    end
  end
end
