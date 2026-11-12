# frozen_string_literal: true

# name: discourse-mute-enhancements
# about: Keeps what users muted or ignored out of search, lets them mute or ignore whole groups, and gives admins per-group defaults for their members.
# version: 0.4
# authors: Hydroiodic
# url: https://github.com/Hydroiodic/discourse-search-tag-filter

enabled_site_setting :mute_enhancements_enabled

register_asset "stylesheets/common/mute-enhancements.scss"

module ::DiscourseMuteEnhancements
  PLUGIN_NAME = "discourse-mute-enhancements"

  # Levels shared by group mutes, the rows they create and group defaults.
  LEVELS = { mute: 1, ignore: 2 }.freeze

  # Core requires ignored_users.expiring_at. Rows created by this plugin last until the plugin
  # removes them, so they use the same date as the "forever" option of core's ignore dialog.
  def self.forever
    1000.years.from_now
  end

  # The settings on a group's Manage > Member preferences page are for admins only, and automatic
  # groups do not have them. feature is the module that implements the setting.
  def self.group_setting_visible?(feature, guardian, group)
    feature.enabled? && guardian.is_admin? && !group.automatic
  end
end

require_relative "lib/discourse_mute_enhancements/engine"

after_initialize do
  reloadable_patch do
    ::Search.prepend(DiscourseMuteEnhancements::SearchExtension)
    ::UserSerializer.prepend(DiscourseMuteEnhancements::UserSerializerExtension)
    ::UsersController.prepend(
      DiscourseMuteEnhancements::SearchSuggestions::UsersControllerExtension,
    )
    ::TagsController.prepend(DiscourseMuteEnhancements::SearchSuggestions::TagsControllerExtension)
  end

  # Search

  # Lets the browser leave muted categories out of the search box suggestions (see
  # SearchSuggestions). Present when the search hides muted categories; the browser reads the
  # other muted categories from core's fields.
  add_to_serializer(
    :current_user,
    :mute_enhancements_default_muted_category_ids,
    include_condition: -> { SiteSetting.mute_enhancements_search_muted_categories },
  ) { DiscourseMuteEnhancements::SearchSuggestions.default_muted_category_ids(object) }

  # Group mutes and ignores (Preferences > Users)

  add_to_serializer(
    :user,
    :mute_enhancements_muted_group_ids,
    include_condition: -> { DiscourseMuteEnhancements::GroupMutes.serialize_for?(scope, object) },
  ) { DiscourseMuteEnhancements::GroupMutes.group_ids(object, :mute).join(",") }

  add_to_serializer(
    :user,
    :mute_enhancements_ignored_group_ids,
    include_condition: -> { DiscourseMuteEnhancements::GroupMutes.serialize_for?(scope, object) },
  ) { DiscourseMuteEnhancements::GroupMutes.group_ids(object, :ignore).join(",") }

  add_to_serializer(
    :user,
    :mute_enhancements_available_groups,
    include_condition: -> { DiscourseMuteEnhancements::GroupMutes.serialize_for?(scope, object) },
  ) do
    DiscourseMuteEnhancements::GroupMutes
      .choosable_groups(object)
      .map { |group| { id: group.id, name: group.name, full_name: group.full_name } }
  end

  register_modifier(:users_controller_update_user_params) do |result, _current_user, params|
    DiscourseMuteEnhancements::GroupMutes.permit_user_params(result, params)
  end

  on(:within_user_updater_transaction) do |user, attributes|
    DiscourseMuteEnhancements::GroupMutes.apply_user_update(user, attributes)
  end

  # Group > Manage > Member preferences: default muted and ignored users and groups for the
  # group's members, preference pages hidden from them, topics muted for them and enhanced-ignore
  # options turned on for them

  add_to_serializer(
    :group_show,
    :mute_enhancements_default_users,
    include_condition: -> do
      DiscourseMuteEnhancements.group_setting_visible?(
        DiscourseMuteEnhancements::GroupDefaultUsers,
        scope,
        object,
      )
    end,
  ) { DiscourseMuteEnhancements::GroupDefaultUsers.usernames(object) }

  add_to_serializer(
    :group_show,
    :mute_enhancements_default_groups,
    include_condition: -> do
      DiscourseMuteEnhancements.group_setting_visible?(
        DiscourseMuteEnhancements::GroupDefaultGroups,
        scope,
        object,
      )
    end,
  ) { DiscourseMuteEnhancements::GroupDefaultGroups.serialize(object) }

  add_to_serializer(
    :group_show,
    :mute_enhancements_hidden_preferences,
    include_condition: -> do
      DiscourseMuteEnhancements.group_setting_visible?(
        DiscourseMuteEnhancements::HiddenPreferences,
        scope,
        object,
      )
    end,
  ) { DiscourseMuteEnhancements::HiddenPreferences.group_pages(object) }

  add_to_serializer(
    :group_show,
    :mute_enhancements_muted_topic_ids,
    include_condition: -> do
      DiscourseMuteEnhancements.group_setting_visible?(
        DiscourseMuteEnhancements::GroupMutedTopics,
        scope,
        object,
      )
    end,
  ) { DiscourseMuteEnhancements::GroupMutedTopics.topic_ids(object) }

  add_to_serializer(
    :group_show,
    :mute_enhancements_enhanced_ignore,
    include_condition: -> do
      DiscourseMuteEnhancements.group_setting_visible?(
        DiscourseMuteEnhancements::GroupEnhancedIgnore,
        scope,
        object,
      )
    end,
  ) { DiscourseMuteEnhancements::GroupEnhancedIgnore.group_options(object) }

  # The pages hidden from the current user. Present only for members with hidden pages.
  add_to_serializer(
    :current_user,
    :mute_enhancements_hidden_preferences,
    include_condition: -> do
      (
        @mute_enhancements_hidden_pages ||=
          DiscourseMuteEnhancements::HiddenPreferences.hidden_pages(object)
      ).present?
    end,
  ) { @mute_enhancements_hidden_pages }

  # Group membership

  # Default users go first, so a user the admin chose by name always gets the level chosen for
  # them. A default group can still add an ignore on top of that mute, as when members set both
  # up themselves.
  on(:user_added_to_group) do |user, group, **|
    DiscourseMuteEnhancements::GroupDefaultUsers.apply(group, [user.id])
    DiscourseMuteEnhancements::GroupDefaultGroups.apply(group, [user.id])
    DiscourseMuteEnhancements::GroupMutedTopics.apply(group, [user.id])
    DiscourseMuteEnhancements::GroupEnhancedIgnore.apply(group, [user.id])
    DiscourseMuteEnhancements::GroupMutes.member_changed(group, user)
  end

  on(:user_removed_from_group) do |user, group|
    DiscourseMuteEnhancements::GroupMutes.member_changed(group, user)
  end

  on(:group_destroyed) do |group, _user_ids|
    DiscourseMuteEnhancements::GroupMutes.group_destroyed(group.id)
    DiscourseMuteEnhancements::GroupDefaultUsers.group_destroyed(group.id)
    DiscourseMuteEnhancements::GroupDefaultGroups.group_destroyed(group.id)
  end
end
