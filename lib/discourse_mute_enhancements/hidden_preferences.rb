# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Preference pages hidden from a group's members, chosen by admins on the group's
  # Manage > User preferences page: Notifications, Tracking and Users, each on its own (none by
  # default). A member gets the pages hidden by all their groups in current_user, and the browser
  # hides their tabs and sends links to them to Account.
  #
  # This only hides the pages. The settings on them still apply, and the server still accepts
  # changes to them, for example from the mute and ignore menu on user cards or the notification
  # level of a category.
  #
  # Admins and moderators always see the pages, so staff cannot lock themselves out. Automatic
  # groups have no such page.
  #
  # Stored as a comma-separated list in a group custom field, which is deleted when none are hidden.
  module HiddenPreferences
    FIELD = "mute_enhancements_hide_preferences"
    PAGES = %w[notifications tracking users].freeze

    class InvalidPages < StandardError
    end

    def self.enabled?
      SiteSetting.mute_enhancements_enabled && SiteSetting.mute_enhancements_group_hide_preferences
    end

    def self.parse(value)
      PAGES & value.to_s.split(",").map(&:strip)
    end

    def self.group_pages(group)
      parse(GroupCustomField.where(group_id: group.id, name: FIELD).pluck(:value).join(","))
    end

    # Replaces the pages hidden from the group's members. Returns whether they changed.
    def self.update(group, pages)
      pages = Array(pages).flat_map { |page| page.to_s.split(",") }.map(&:strip).compact_blank
      raise InvalidPages, (pages - PAGES).join(", ") if (pages - PAGES).present?
      pages = PAGES & pages
      return false if pages == group_pages(group)

      GroupCustomField.transaction do
        GroupCustomField.where(group_id: group.id, name: FIELD).delete_all
        if pages.present?
          GroupCustomField.create!(group_id: group.id, name: FIELD, value: pages.join(","))
        end
      end
      true
    end

    def self.hidden_pages(user)
      return [] if !enabled? || user.nil? || user.staff?
      values =
        GroupCustomField.where(
          name: FIELD,
          group_id: GroupUser.where(user_id: user.id).select(:group_id),
        ).pluck(:value)
      parse(values.join(","))
    end
  end
end
