# frozen_string_literal: true

class CreateMuteEnhancementsTables < ActiveRecord::Migration[8.1]
  def change
    # Groups a user muted or ignored (level 1 = mute, 2 = ignore). One level per group.
    create_table :mute_enhancements_group_mutes do |t|
      t.integer :user_id, null: false
      t.integer :group_id, null: false
      t.integer :level, null: false
      t.timestamps
    end
    add_index :mute_enhancements_group_mutes, %i[user_id group_id], unique: true
    add_index :mute_enhancements_group_mutes, :group_id

    # The muted_users / ignored_users rows that group mutes created, so they can be removed again
    # without touching the ones the user set up themselves.
    create_table :mute_enhancements_derived_mutes do |t|
      t.integer :user_id, null: false
      t.integer :target_user_id, null: false
      t.integer :level, null: false
      t.datetime :created_at, null: false
    end
    add_index :mute_enhancements_derived_mutes,
              %i[user_id target_user_id level],
              unique: true,
              name: "idx_mute_enhancements_derived_mutes_unique"
    add_index :mute_enhancements_derived_mutes, :target_user_id

    # Users a group's members mute or ignore by default. One level per user.
    create_table :mute_enhancements_group_default_users do |t|
      t.integer :group_id, null: false
      t.integer :target_user_id, null: false
      t.integer :level, null: false
      t.timestamps
    end
    add_index :mute_enhancements_group_default_users,
              %i[group_id target_user_id],
              unique: true,
              name: "idx_mute_enhancements_group_default_users_unique"
  end
end
