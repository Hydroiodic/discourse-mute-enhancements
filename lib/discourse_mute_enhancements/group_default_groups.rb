# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Groups that a group's members mute or ignore by default, set by admins next to the default
  # users (GroupDefaultUsers) on the group's Manage > Member preferences page. A member who joins
  # gets a group mute of their own (see GroupMutes) for each of them, as if they had muted or
  # ignored the group in their preferences, so it follows that group's members from then on.
  # Otherwise it works like the default users:
  #
  # - a member who already muted or ignored that group keeps what they chose;
  # - the group mute belongs to the member, who can remove it in Preferences > Users;
  # - leaving the group, or removing a default, leaves it in place;
  # - when a default is added, admins choose whether current members get it too.
  #
  # Any group can be a default except automatic groups and the group itself, including hidden
  # groups, which members cannot mute themselves (GroupMutes.mutable_groups). This was chosen on
  # purpose: admins see every group anyway, and it is acceptable that members see a hidden group's
  # name in their preferences and can tell who is in it from who they mute or ignore. Members can
  # remove such a group mute, but cannot add it back themselves.
  #
  # Kept in a group custom field, group id => level (see GroupLevels).
  module GroupDefaultGroups
    FIELD = "mute_enhancements_default_groups"

    class InvalidGroups < StandardError
    end

    def self.enabled?
      GroupDefaultUsers.enabled? && GroupMutes.enabled?
    end

    # The group's defaults, group id => level.
    def self.levels(group)
      GroupLevels.read(group.id, FIELD)
    end

    def self.group_ids(group)
      levels = levels(group).sort.to_h
      LEVELS.to_h do |level, value|
        [
          :"#{level == :mute ? "muted" : "ignored"}_group_ids",
          levels.filter_map { |id, l| id if l == value },
        ]
      end
    end

    def self.names(ids)
      Group.where(id: ids).order(:name).pluck(:name)
    end

    # Groups that can be defaults: any group but automatic ones and the group itself.
    def self.eligible_groups(group)
      Group.where(automatic: false).where.not(id: group.id)
    end

    # What the Member preferences page offers.
    def self.choosable_groups(group)
      eligible_groups(group).order(:name)
    end

    def self.serialize(group)
      group_ids(group).merge(
        available_groups:
          choosable_groups(group).map { |g| { id: g.id, name: g.name, full_name: g.full_name } },
      )
    end

    # Replaces the group's default groups. A group in both lists is ignored. Returns the ids of
    # current members who got a new group mute (none unless update_existing_users).
    def self.update(group, muted_group_ids:, ignored_group_ids:, update_existing_users:)
      ignored = parse_ids(ignored_group_ids)
      muted = parse_ids(muted_group_ids) - ignored
      desired =
        muted.to_h { |id| [id, LEVELS[:mute]] }.merge(ignored.to_h { |id| [id, LEVELS[:ignore]] })
      current = levels(group)

      added = desired.keys - current.keys
      invalid = added - eligible_groups(group).where(id: added).pluck(:id)
      raise InvalidGroups, (names(invalid).presence || invalid).join(", ") if invalid.present?

      changed = desired.reject { |group_id, level| current[group_id] == level }
      GroupLevels.write(group.id, FIELD, desired) if desired != current

      return [] if !update_existing_users || changed.empty?
      apply(group, nil, only_target_ids: changed.keys)
    end

    # Gives the given members of the group (all members when nil) the group's default groups, or
    # only the defaults for only_target_ids. Returns the ids of members who got a new group mute.
    def self.apply(group, member_ids, only_target_ids: nil)
      return [] if !enabled? || group.automatic || member_ids&.empty?

      defaults = levels(group)
      defaults = defaults.slice(*only_target_ids) if only_target_ids
      defaults = defaults.slice(*Group.where(id: defaults.keys, automatic: false).pluck(:id))
      return [] if defaults.empty?

      members = GroupUser.where(group_id: group.id)
      members = members.where(user_id: member_ids) if member_ids
      user_ids =
        UserStore.merge(
          GroupMutes::STORE,
          members.pluck(:user_id).to_h { |user_id| [user_id, defaults] },
          keep_existing: true,
        )

      GroupMutes.reconcile(user_ids:) if user_ids.present?
      user_ids
    end

    def self.group_destroyed(group_id)
      GroupCustomField.where(group_id:, name: FIELD).delete_all
      GroupLevels.remove_everywhere(FIELD, group_id)
    end

    def self.parse_ids(value)
      Array(value)
        .flat_map { |item| item.to_s.split(",") }
        .map(&:strip)
        .grep(/\A\d+\z/)
        .map(&:to_i)
        .uniq
    end
    private_class_method :parse_ids
  end
end
