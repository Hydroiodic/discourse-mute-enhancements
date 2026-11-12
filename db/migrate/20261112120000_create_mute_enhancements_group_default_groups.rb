# frozen_string_literal: true

class CreateMuteEnhancementsGroupDefaultGroups < ActiveRecord::Migration[8.1]
  def change
    # Groups a group's members mute or ignore by default (level 1 = mute, 2 = ignore). One level
    # per group.
    create_table :mute_enhancements_group_default_groups do |t|
      t.integer :group_id, null: false
      t.integer :target_group_id, null: false
      t.integer :level, null: false
      t.timestamps
    end
    add_index :mute_enhancements_group_default_groups,
              %i[group_id target_group_id],
              unique: true,
              name: "idx_mute_enhancements_group_default_groups_unique"
    add_index :mute_enhancements_group_default_groups, :target_group_id
  end
end
