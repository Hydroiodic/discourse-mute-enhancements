# frozen_string_literal: true

class SplitMuteEnhancementsHiddenPreferences < ActiveRecord::Migration[8.1]
  # The option used to hide Notifications and Users together, stored as "t". It now lists the
  # hidden pages, and Notifications can no longer be hidden.
  def up
    execute <<~SQL
      UPDATE group_custom_fields
      SET value = 'users'
      WHERE name = 'mute_enhancements_hide_preferences' AND value = 't'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
