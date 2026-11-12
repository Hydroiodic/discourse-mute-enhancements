# frozen_string_literal: true

module DiscourseMuteEnhancements
  # The search box suggests users after `@` through /u/search/users, and categories and tags after
  # `#`: categories in the browser, tags through /tags/filter/search. The full page search's
  # "users" and "categories/tags" types use the same lookups. So do mentions in the composer and
  # chat and the user and tag choosers, which should still list everyone, so the browser adds
  # PARAM to the lookups made from search (see lib/search-suggestions.js) and only those leave out
  # what the user muted or ignored. Like the users, categories and tags sections of the results,
  # they do so with no exceptions.
  module SearchSuggestions
    PARAM = "mute_enhancements_search"

    def self.hidden_ids(controller, kind)
      user = controller.current_user
      return [] if !SiteSetting.mute_enhancements_enabled || !user
      return [] if controller.params[PARAM].to_s != "true"
      HiddenIds.public_send(kind, user)
    end

    # The browser leaves out the categories in the current user's muted_category_ids and
    # indirectly_muted_category_ids, which core keeps current when the user changes a category's
    # level. With mute_all_categories_by_default, the categories the user has not set are muted
    # too and are in neither list, so they are sent separately.
    def self.default_muted_category_ids(user)
      return [] if !SiteSetting.mute_all_categories_by_default
      CategoryUser.muted_category_ids(user) -
        CategoryUser.lookup(user, :muted).pluck(:category_id) -
        CategoryUser.indirectly_muted_category_ids(user)
    end

    module UsersControllerExtension
      def search_users
        ids = SearchSuggestions.hidden_ids(self, :user_ids)
        return super() if ids.blank?
        # UserSearch builds its queries from User, so a scope on the class reaches all of them.
        User.where.not(id: ids).scoping { super() }
      end
    end

    module TagsControllerExtension
      def search
        # Core leaves the selected tags out of the results, which is all it does with them unless
        # filterForInput is set (tag choosers set it, search never does). With it, selected tags
        # would also count as parent tags and rule out other tags of a one-per-topic group.
        if !ActiveModel::Type::Boolean.new.cast(params[:filterForInput])
          ids = SearchSuggestions.hidden_ids(self, :tag_ids)
          if ids.present?
            params[:selected_tag_ids] = Array(params[:selected_tag_ids]).map(&:to_i) | ids
          end
        end
        super()
      end
    end
  end
end
