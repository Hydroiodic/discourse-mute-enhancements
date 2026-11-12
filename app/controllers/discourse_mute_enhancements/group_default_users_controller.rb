# frozen_string_literal: true

module DiscourseMuteEnhancements
  class GroupDefaultUsersController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_admin

    # PUT /mute-enhancements/groups/:group_id/default-users
    #   muted_usernames, ignored_usernames: comma-separated
    #   update_existing_users: "true" to give current members the defaults that were added
    def update
      raise Discourse::NotFound if !GroupDefaultUsers.enabled?

      group = Group.find(params.require(:group_id))
      raise Discourse::InvalidParameters.new(:group_id) if group.automatic

      applied_user_count =
        GroupDefaultUsers.update(
          group,
          muted_usernames: params[:muted_usernames],
          ignored_usernames: params[:ignored_usernames],
          update_existing_users: params[:update_existing_users].to_s == "true",
        )

      defaults = GroupDefaultUsers.usernames(group)
      StaffActionLogger.new(current_user).log_custom(
        "mute_enhancements_group_default_users",
        group: group.name,
        muted: defaults[:muted_usernames].join(", "),
        ignored: defaults[:ignored_usernames].join(", "),
        applied_user_count:,
      )

      render json: defaults.merge(applied_user_count:)
    rescue GroupDefaultUsers::InvalidUsers => e
      render_json_error(
        I18n.t("mute_enhancements.errors.staff_default_users", usernames: e.message),
      )
    end
  end
end
