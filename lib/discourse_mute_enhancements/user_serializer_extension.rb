# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Prepended to ::UserSerializer.
  module UserSerializerExtension
    # group_users lists every group the user is in, with ids, to the user themselves, while
    # `groups` only lists the ones they can see. Members of a group they cannot see (visibility
    # "group owners", or "staff" for a non-staff member) would learn it exists and that they are
    # in it. Admins still get the full list.
    def group_users
      relation = super
      if !SiteSetting.mute_enhancements_enabled ||
           !SiteSetting.mute_enhancements_hide_invisible_group_users || scope.is_admin?
        return relation
      end
      relation.where(group_id: Group.visible_groups(scope.user).select(:id))
    end

    # The muted and ignored users lists in preferences leave out the rows group mutes created;
    # the groups are listed instead. GroupMutes.permit_user_params keeps those rows when the page
    # saves the muted users list.
    def muted_usernames
      return super if !GroupMutes.enabled?
      MutedUser
        .where(user_id: object.id)
        .where.not(muted_user_id: GroupMutes.derived_target_ids(object, :mute))
        .joins(:muted_user)
        .pluck(:username)
    end

    def ignored_usernames
      return super if !GroupMutes.enabled?
      IgnoredUser
        .where(user_id: object.id)
        .where.not(ignored_user_id: GroupMutes.derived_target_ids(object, :ignore))
        .joins(:ignored_user)
        .pluck(:username)
    end
  end
end
