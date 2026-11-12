# frozen_string_literal: true

module DiscourseMuteEnhancements
  # A group that members of the group mute or ignore by default.
  class GroupDefaultGroup < ActiveRecord::Base
    self.table_name = "mute_enhancements_group_default_groups"

    belongs_to :group
    belongs_to :target_group, class_name: "Group"
  end
end
