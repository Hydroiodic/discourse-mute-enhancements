# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Marks a muted_users / ignored_users row (user_id muted or ignored target_user_id) that a group
  # mute created. The marker stays when the row itself is deleted, e.g. when the user unmutes that
  # one member from the user card, so the group mute does not bring the row back.
  class DerivedMute < ActiveRecord::Base
    self.table_name = "mute_enhancements_derived_mutes"
  end
end
