# frozen_string_literal: true

module DiscourseMuteEnhancements
  # What a user muted or ignored, as far as the search settings hide it.
  module HiddenIds
    # Ignored users (`mute_enhancements_search_ignored_users`) and muted users
    # (`mute_enhancements_search_muted_users`). Never the user themselves or staff, as in
    # IgnoredUser.ignored_ids_for.
    def self.user_ids(user)
      ids = []
      if SiteSetting.mute_enhancements_search_ignored_users
        ids.concat(IgnoredUser.ignored_ids_for(user))
      end
      if SiteSetting.mute_enhancements_search_muted_users
        ids.concat(
          User
            .where(id: MutedUser.where(user_id: user.id).select(:muted_user_id))
            .where(admin: false, moderator: false)
            .where.not(id: user.id)
            .pluck(:id),
        )
      end
      ids.uniq
    end

    # Muted categories, including subcategories of muted categories and, with
    # mute_all_categories_by_default, every category the user has not set otherwise.
    def self.category_ids(user)
      return [] if !SiteSetting.mute_enhancements_search_muted_categories
      CategoryUser.muted_category_ids(user)
    end

    def self.tag_ids(user)
      return [] if !SiteSetting.mute_enhancements_search_muted_tags || !SiteSetting.tagging_enabled
      TagUser.lookup(user, :muted).pluck(:tag_id)
    end
  end
end
