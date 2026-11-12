# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Groups that a group's members mute or ignore by default, set by admins next to the default
  # users (GroupDefaultUsers) on the group's Manage → User preferences page. A member who joins gets a group mute
  # of their own (see GroupMutes) for each of them, as if they had muted or ignored the group in
  # their preferences, so it follows that group's members from then on. Otherwise it works like
  # the default users:
  #
  # - a member who already muted or ignored that group keeps what they chose;
  # - the group mute belongs to the member, who can remove it in Preferences → Users;
  # - leaving the group, or removing a default, leaves it in place;
  # - when a default is added, admins choose whether current members get it too.
  #
  # Any group can be a default except automatic groups and the group itself, including hidden
  # groups, which members cannot mute themselves (GroupMutes.mutable_groups). This was chosen on
  # purpose: admins see every group anyway, and it is acceptable that members see a hidden group's
  # name in their preferences and can tell who is in it from who they mute or ignore. Members can
  # remove such a group mute, but cannot add it back themselves.
  module GroupDefaultGroups
    class InvalidGroups < StandardError
    end

    def self.enabled?
      GroupDefaultUsers.enabled? && GroupMutes.enabled?
    end

    def self.eligible_groups(group)
      Group.where(automatic: false).where.not(id: group.id)
    end

    def self.group_ids(group)
      rows =
        GroupDefaultGroup
          .where(group_id: group.id)
          .order(:target_group_id)
          .pluck(:level, :target_group_id)
      LEVELS.to_h do |level, value|
        [
          :"#{level == :mute ? "muted" : "ignored"}_group_ids",
          rows.filter_map { |l, id| id if l == value },
        ]
      end
    end

    def self.names(ids)
      Group.where(id: ids).order(:name).pluck(:name)
    end

    # What the User preferences page offers.
    def self.choosable_groups(group)
      eligible_groups(group).order(:name)
    end

    def self.serialize(group)
      group_ids(group).merge(
        available_groups:
          choosable_groups(group).map { |g| { id: g.id, name: g.name, full_name: g.full_name } },
      )
    end

    # Replaces the group's default groups. A group in both lists is ignored. Returns the ids of current members who got a new group
    # mute (none unless update_existing_users).
    def self.update(group, muted_group_ids:, ignored_group_ids:, update_existing_users:)
      ignored = parse_ids(ignored_group_ids)
      muted = parse_ids(muted_group_ids) - ignored
      desired =
        muted.to_h { |id| [id, LEVELS[:mute]] }.merge(ignored.to_h { |id| [id, LEVELS[:ignore]] })
      current = GroupDefaultGroup.where(group_id: group.id).pluck(:target_group_id, :level).to_h

      added = desired.keys - current.keys
      invalid = added - eligible_groups(group).where(id: added).pluck(:id)
      raise InvalidGroups, (names(invalid).presence || invalid).join(", ") if invalid.present?

      changed = desired.reject { |group_id, level| current[group_id] == level }

      GroupDefaultGroup.transaction do
        GroupDefaultGroup
          .where(group_id: group.id)
          .where.not(target_group_id: desired.keys)
          .delete_all
        changed.each do |target_group_id, level|
          GroupDefaultGroup.upsert(
            { group_id: group.id, target_group_id:, level: },
            unique_by: %i[group_id target_group_id],
            update_only: %i[level],
          )
        end
      end

      return [] if !update_existing_users || changed.empty?
      apply(group, nil, only_target_ids: changed.keys)
    end

    # Gives the given members of the group (all members when nil) the group's default groups, or
    # only the defaults for only_target_ids. Returns the ids of members who got a new group mute.
    def self.apply(group, member_ids, only_target_ids: nil)
      return [] if !enabled? || group.automatic || member_ids&.empty?

      defaults = GroupDefaultGroup.where(group_id: group.id)
      defaults = defaults.where(target_group_id: only_target_ids) if only_target_ids
      return [] if !defaults.exists?

      params = { group_id: group.id, member_ids:, target_ids: only_target_ids, now: Time.zone.now }
      user_ids = DB.query_single(<<~SQL, params).uniq
        INSERT INTO mute_enhancements_group_mutes (user_id, group_id, level, created_at, updated_at)
        SELECT gu.user_id, d.target_group_id, d.level, :now, :now
        FROM mute_enhancements_group_default_groups d
        JOIN groups t ON t.id = d.target_group_id AND NOT t.automatic
        JOIN group_users gu ON gu.group_id = d.group_id
          #{member_ids ? "AND gu.user_id IN (:member_ids)" : ""}
        WHERE d.group_id = :group_id
          #{only_target_ids ? "AND d.target_group_id IN (:target_ids)" : ""}
        ON CONFLICT (user_id, group_id) DO NOTHING
        RETURNING user_id
      SQL

      GroupMutes.reconcile(user_ids:) if user_ids.present?
      user_ids
    end

    def self.group_destroyed(group_id)
      GroupDefaultGroup
        .where(group_id:)
        .or(GroupDefaultGroup.where(target_group_id: group_id))
        .delete_all
    end

    def self.parse_ids(value)
      Array(value)
        .flat_map { |v| v.to_s.split(",") }
        .map(&:strip)
        .select { |id| id.match?(/\A\d+\z/) }
        .map(&:to_i)
        .uniq
    end
  end
end
