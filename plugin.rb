# frozen_string_literal: true

# name: discourse-mute-enhancements
# about: Keeps what a user muted or ignored out of search, lets users mute or ignore whole groups, and lets admins set default muted and ignored users for a group's members.
# version: 0.3
# authors: Hydroiodic

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
end

require_relative "lib/discourse_mute_enhancements/search_terms"
require_relative "lib/discourse_mute_enhancements/hidden_ids"
require_relative "lib/discourse_mute_enhancements/muted_tags_filter"
require_relative "lib/discourse_mute_enhancements/muted_categories_filter"
require_relative "lib/discourse_mute_enhancements/ignored_users_filter"
require_relative "lib/discourse_mute_enhancements/search_extension"
require_relative "lib/discourse_mute_enhancements/search_suggestions"

after_initialize do
  require_relative "app/models/discourse_mute_enhancements/group_mute"
  require_relative "app/models/discourse_mute_enhancements/derived_mute"
  require_relative "app/models/discourse_mute_enhancements/group_default_user"
  require_relative "lib/discourse_mute_enhancements/group_mutes"
  require_relative "lib/discourse_mute_enhancements/group_default_users"
  require_relative "lib/discourse_mute_enhancements/user_serializer_extension"
  require_relative "app/controllers/discourse_mute_enhancements/group_default_users_controller"
  require_relative "app/jobs/scheduled/mute_enhancements_reconcile_group_mutes"

  reloadable_patch do
    ::Search.prepend(DiscourseMuteEnhancements::SearchExtension)
    ::UserSerializer.prepend(DiscourseMuteEnhancements::UserSerializerExtension)
    ::UsersController.prepend(
      DiscourseMuteEnhancements::SearchSuggestions::UsersControllerExtension,
    )
    ::TagsController.prepend(DiscourseMuteEnhancements::SearchSuggestions::TagsControllerExtension)
  end

  # Suggestions in the search box (see SearchSuggestions). Present when the search hides muted
  # categories; the browser reads the other muted categories from core's fields.
  add_to_serializer(
    :current_user,
    :mute_enhancements_default_muted_category_ids,
    include_condition: -> { SiteSetting.mute_enhancements_search_muted_categories },
  ) { DiscourseMuteEnhancements::SearchSuggestions.default_muted_category_ids(object) }

  Discourse::Application.routes.append do
    put "/mute-enhancements/groups/:group_id/default-users" =>
          "discourse_mute_enhancements/group_default_users#update",
        :constraints => {
          group_id: /\d+/,
        }
  end

  # Group mutes and ignores (preferences → Users)

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

  # Default muted and ignored users for a group's members (group → Manage → Membership)

  add_to_serializer(
    :group_show,
    :mute_enhancements_default_users,
    include_condition: -> do
      DiscourseMuteEnhancements::GroupDefaultUsers.enabled? && scope.is_admin? && !object.automatic
    end,
  ) { DiscourseMuteEnhancements::GroupDefaultUsers.usernames(object) }

  # Keeping both in sync with group membership

  on(:user_added_to_group) do |user, group, **|
    DiscourseMuteEnhancements::GroupDefaultUsers.apply(group, [user.id])
    DiscourseMuteEnhancements::GroupMutes.member_changed(group, user)
  end

  on(:user_removed_from_group) do |user, group|
    DiscourseMuteEnhancements::GroupMutes.member_changed(group, user)
  end

  on(:group_destroyed) do |group, _user_ids|
    DiscourseMuteEnhancements::GroupMutes.group_destroyed(group.id)
    DiscourseMuteEnhancements::GroupDefaultUser.where(group_id: group.id).delete_all
  end
end
