# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Per-user JSON objects kept in core's plugin_store_rows (PluginStore), so that the plugin needs
  # no tables, and no migrations, of its own. Each row has the key "<kind>:<user id>" and an
  # object from ids to integers as its value:
  #
  # - group_mutes: the groups the user muted or ignored, group id => level (see GroupMutes);
  # - derived_mutes, derived_ignores: the members whose muted_users / ignored_users row a group
  #   mute created, user id => 1.
  #
  # Each write changes the objects in one SQL statement, adding or removing keys, so writes to the
  # same row at the same time do not undo each other. Rows left empty are deleted.
  #
  # user_custom_fields would be the obvious place, but core's save_custom_fields writes back all
  # of a user's fields from the copy it loaded, which drops what was written in the meantime, and
  # reading custom_fields loads every row of the user, which can be thousands of members here.
  module UserStore
    KINDS = %w[group_mutes derived_mutes derived_ignores].freeze

    def self.key(kind, user_id)
      "#{kind}:#{user_id}"
    end

    # The user's object, with integer keys and values.
    def self.read(kind, user_id)
      value = PluginStoreRow.where(plugin_name: PLUGIN_NAME, key: key(kind, user_id)).pick(:value)
      value.present? ? JSON.parse(value).to_h { |id, v| [id.to_i, v.to_i] } : {}
    end

    # SQL selecting (user_id, item_id, value) for the entries of kind, of the users whose keys are
    # in the :<kind>_keys parameter when only_listed, or of everyone. Needs the parameters from
    # sql_params.
    def self.entries_sql(kind, only_listed:)
      check_kind!(kind)
      <<~SQL
        SELECT split_part(r.key, ':', 2)::int AS user_id, e.key::int AS item_id, e.value::int AS value
        FROM plugin_store_rows r
        CROSS JOIN LATERAL jsonb_each_text(r.value::jsonb) e
        WHERE r.plugin_name = :plugin_name
          AND starts_with(r.key, '#{kind}:')
          #{only_listed ? "AND r.key IN (:#{kind}_keys)" : ""}
      SQL
    end

    def self.sql_params(kinds, user_ids)
      params = { plugin_name: PLUGIN_NAME }
      Array(kinds).each do |kind|
        params[:"#{kind}_keys"] = Array(user_ids).map { |user_id| key(kind, user_id) }
      end
      params
    end

    # The users whose object of kind has item_id.
    def self.user_ids_with(kind, item_id)
      check_kind!(kind)
      DB.query_single(<<~SQL, plugin_name: PLUGIN_NAME, item: item_id.to_s)
        SELECT split_part(key, ':', 2)::int
        FROM plugin_store_rows
        WHERE plugin_name = :plugin_name
          AND starts_with(key, '#{kind}:')
          AND CASE WHEN plugin_name = :plugin_name THEN jsonb_exists(value::jsonb, :item) END
      SQL
    end

    # Adds entries, { user id => { item id => value } }. With keep_existing, items a user already
    # has keep their value. Returns the ids of users whose object changed.
    def self.merge(kind, entries, keep_existing: false)
      check_kind!(kind)
      entries = entries.reject { |_, items| items.empty? }
      return [] if entries.empty?

      merged =
        (
          if keep_existing
            "EXCLUDED.value::jsonb || r.value::jsonb"
          else
            "r.value::jsonb || EXCLUDED.value::jsonb"
          end
        )
      DB.query_single(
        <<~SQL,
        INSERT INTO plugin_store_rows AS r (plugin_name, key, type_name, value)
        SELECT :plugin_name, :prefix || e.key, 'JSON', e.value::text
        FROM jsonb_each(CAST(:entries AS jsonb)) e
        ON CONFLICT (plugin_name, key) DO UPDATE
          SET value = (#{merged})::text
          WHERE (#{merged}) <> r.value::jsonb
        RETURNING split_part(r.key, ':', 2)::int
      SQL
        plugin_name: PLUGIN_NAME,
        prefix: "#{kind}:",
        entries: entries.to_json,
      )
    end

    # Removes items, { user id => [item ids] }.
    def self.remove(kind, items_by_user)
      check_kind!(kind)
      items_by_user = items_by_user.reject { |_, ids| ids.empty? }
      return if items_by_user.empty?

      DB.exec(
        <<~SQL,
          UPDATE plugin_store_rows r
          SET value = (r.value::jsonb - ARRAY(SELECT jsonb_array_elements_text(e.value)))::text
          FROM jsonb_each(CAST(:items AS jsonb)) e
          WHERE r.plugin_name = :plugin_name AND r.key = :prefix || e.key
        SQL
        plugin_name: PLUGIN_NAME,
        prefix: "#{kind}:",
        items: items_by_user.transform_values { |ids| ids.map(&:to_s) }.to_json,
      )
      delete_empty(kind, items_by_user.keys)
    end

    # Sets and removes items of one user's object at once.
    def self.change(kind, user_id, set:, remove:)
      check_kind!(kind)
      return if set.empty? && remove.empty?

      DB.exec(
        <<~SQL,
          INSERT INTO plugin_store_rows AS r (plugin_name, key, type_name, value)
          VALUES (:plugin_name, :key, 'JSON', :set)
          ON CONFLICT (plugin_name, key) DO UPDATE
            SET value = ((r.value::jsonb - string_to_array(:remove, ',')) || EXCLUDED.value::jsonb)::text
        SQL
        plugin_name: PLUGIN_NAME,
        key: key(kind, user_id),
        set: set.to_json,
        remove: remove.join(","),
      )
      delete_empty(kind, [user_id])
    end

    # Removes item_id from every user's object of kind. Returns the ids of users who had it.
    def self.remove_everywhere(kind, item_id)
      user_ids = user_ids_with(kind, item_id)
      remove(kind, user_ids.to_h { |user_id| [user_id, [item_id]] })
      user_ids
    end

    # Removes the items that no longer exist: those not returned by the SQL that selects the ids
    # still valid. Returns the ids of users who lost items.
    def self.remove_missing(kind, valid_ids_sql)
      check_kind!(kind)
      rows = DB.query(<<~SQL, sql_params([], []))
        SELECT user_id, array_agg(item_id) AS item_ids
        FROM (#{entries_sql(kind, only_listed: false)}) entries
        WHERE item_id NOT IN (#{valid_ids_sql})
        GROUP BY user_id
      SQL
      remove(kind, rows.to_h { |row| [row.user_id, row.item_ids] })
      rows.map(&:user_id)
    end

    # Deletes every row of users that no longer exist.
    def self.delete_deleted_users
      DB.exec(<<~SQL, plugin_name: PLUGIN_NAME)
        DELETE FROM plugin_store_rows r
        WHERE r.plugin_name = :plugin_name
          AND NOT EXISTS (SELECT 1 FROM users u WHERE u.id = split_part(r.key, ':', 2)::int)
      SQL
    end

    def self.delete_empty(kind, user_ids)
      DB.exec(<<~SQL, plugin_name: PLUGIN_NAME, keys: user_ids.map { |user_id| key(kind, user_id) })
        DELETE FROM plugin_store_rows
        WHERE plugin_name = :plugin_name
          AND key IN (:keys)
          AND CASE WHEN plugin_name = :plugin_name THEN value::jsonb = '{}'::jsonb END
      SQL
    end
    private_class_method :delete_empty

    def self.check_kind!(kind)
      raise ArgumentError, "unknown kind: #{kind}" if !KINDS.include?(kind)
    end
    private_class_method :check_kind!
  end
end
