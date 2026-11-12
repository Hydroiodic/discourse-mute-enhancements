# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Saves both the default users and, when group mutes are enabled, the default groups of a group.
  class GroupDefaultUsersController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_admin

    # PUT /mute-enhancements/groups/:group_id/default-users
    #   muted_usernames, ignored_usernames: comma-separated
    #   muted_group_ids, ignored_group_ids: comma-separated; the default groups are left as they
    #     are when neither is given
    #   update_existing_users: "true" to give current members the defaults that were added
    def update
      raise Discourse::NotFound if !GroupDefaultUsers.enabled?

      group = Group.find(params.require(:group_id))
      raise Discourse::InvalidParameters.new(:group_id) if group.automatic

      update_existing_users = params[:update_existing_users].to_s == "true"
      with_groups =
        GroupDefaultGroups.enabled? &&
          (params.key?(:muted_group_ids) || params.key?(:ignored_group_ids))

      # Both are saved or neither: an invalid group rolls back the users too.
      applied_user_ids =
        ActiveRecord::Base.transaction do
          ids =
            GroupDefaultUsers.update(
              group,
              muted_usernames: params[:muted_usernames],
              ignored_usernames: params[:ignored_usernames],
              update_existing_users:,
            )
          next ids if !with_groups
          ids |
            GroupDefaultGroups.update(
              group,
              muted_group_ids: params[:muted_group_ids],
              ignored_group_ids: params[:ignored_group_ids],
              update_existing_users:,
            )
        end

      defaults = GroupDefaultUsers.usernames(group)
      defaults.merge!(GroupDefaultGroups.group_ids(group)) if GroupDefaultGroups.enabled?

      details = {
        group: group.name,
        muted: defaults[:muted_usernames].join(", "),
        ignored: defaults[:ignored_usernames].join(", "),
      }
      if GroupDefaultGroups.enabled?
        details[:muted_groups] = GroupDefaultGroups.names(defaults[:muted_group_ids]).join(", ")
        details[:ignored_groups] = GroupDefaultGroups.names(defaults[:ignored_group_ids]).join(", ")
      end
      StaffActionLogger.new(current_user).log_custom(
        "mute_enhancements_group_default_users",
        **details,
        applied_user_count: applied_user_ids.size,
      )

      render json: defaults.merge(applied_user_count: applied_user_ids.size)
    rescue GroupDefaultUsers::InvalidUsers => e
      render_json_error(
        I18n.t("mute_enhancements.errors.staff_default_users", usernames: e.message),
      )
    rescue GroupDefaultGroups::InvalidGroups => e
      render_json_error(
        I18n.t("mute_enhancements.errors.invalid_default_groups", groups: e.message),
      )
    end
  end
end
