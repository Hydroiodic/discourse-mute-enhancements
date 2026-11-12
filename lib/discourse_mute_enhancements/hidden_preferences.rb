# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Groups whose members do not see Preferences → Notifications and Preferences → Users, turned on
  # by admins on the group's Membership page (off by default). A member of any such group gets the
  # pages in current_user, and the browser hides their tabs and sends links to them to Account.
  #
  # This only hides the pages. The settings on them still apply, and the server still accepts
  # changes to them, for example from the mute and ignore menu on user cards.
  #
  # Admins and moderators always see the pages, so staff cannot lock themselves out. Automatic
  # groups cannot turn it on, as they have no Membership page.
  module HiddenPreferences
    FIELD = "mute_enhancements_hide_preferences"
    PAGES = %w[notifications users].freeze

    def self.enabled?
      SiteSetting.mute_enhancements_enabled && SiteSetting.mute_enhancements_group_hide_preferences
    end

    def self.group_enabled?(group)
      GroupCustomField.exists?(group_id: group.id, name: FIELD)
    end

    # Returns whether it changed.
    def self.update(group, enabled)
      return false if enabled == group_enabled?(group)
      if enabled
        GroupCustomField.create!(group_id: group.id, name: FIELD, value: "t")
      else
        GroupCustomField.where(group_id: group.id, name: FIELD).delete_all
      end
      true
    end

    def self.hidden_for?(user)
      return false if !enabled? || user.nil? || user.staff?
      GroupCustomField.where(
        name: FIELD,
        group_id: GroupUser.where(user_id: user.id).select(:group_id),
      ).exists?
    end
  end
end
