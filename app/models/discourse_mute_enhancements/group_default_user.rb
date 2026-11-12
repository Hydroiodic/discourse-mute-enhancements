# frozen_string_literal: true

module DiscourseMuteEnhancements
  # A user that members of the group mute or ignore by default.
  class GroupDefaultUser < ActiveRecord::Base
    self.table_name = "mute_enhancements_group_default_users"

    belongs_to :group
    belongs_to :target_user, class_name: "User"
  end
end
