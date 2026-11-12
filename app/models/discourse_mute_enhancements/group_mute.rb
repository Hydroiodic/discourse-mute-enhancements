# frozen_string_literal: true

module DiscourseMuteEnhancements
  # A group the user muted or ignored. GroupMutes turns it into muted_users / ignored_users rows
  # for the group's members.
  class GroupMute < ActiveRecord::Base
    self.table_name = "mute_enhancements_group_mutes"

    belongs_to :user
    belongs_to :group
  end
end
