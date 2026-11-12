# frozen_string_literal: true

module DiscourseMuteEnhancements
  # A map from ids to LEVELS kept as a JSON object in one group custom field, which is deleted when
  # the map is empty. GroupDefaultUsers and GroupDefaultGroups keep a group's defaults in one each.
  module GroupLevels
    def self.read(group_id, field)
      value = GroupCustomField.where(group_id:, name: field).order(:id).pick(:value)
      value.present? ? JSON.parse(value).to_h { |id, level| [id.to_i, level.to_i] } : {}
    end

    def self.write(group_id, field, levels)
      update(group_id, field) { levels }
    end

    # Replaces the map with what the block returns for the current one. Locks the group, so that
    # two writes at once neither leave two fields nor lose one of the changes.
    def self.update(group_id, field)
      GroupCustomField.transaction do
        DB.exec("SELECT 1 FROM groups WHERE id = :group_id FOR UPDATE", group_id:)
        levels = yield read(group_id, field)
        GroupCustomField.where(group_id:, name: field).delete_all
        if levels.present?
          GroupCustomField.create!(group_id:, name: field, value: levels.sort.to_h.to_json)
        end
      end
    end

    # Removes id from the map of every group.
    def self.remove_everywhere(field, id)
      group_ids = DB.query_single(<<~SQL, field:, id: id.to_s)
        SELECT group_id
        FROM group_custom_fields
        WHERE name = :field
          AND CASE WHEN name = :field THEN jsonb_exists(value::jsonb, :id) END
      SQL
      group_ids.each { |group_id| update(group_id, field) { |levels| levels.except(id) } }
    end
  end
end
