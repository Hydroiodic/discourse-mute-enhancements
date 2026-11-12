# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Prepended to ::Search. Core runs Search#apply_filters inside Search#posts_query, which every
  # search over posts and topics goes through (header search, full page search, `in:all`,
  # `in:all-posts`, pagination). discourse-ai's semantic search builds its own query and calls
  # Search#apply_filters on it too, so hooking here covers both.
  #
  # Only searches by a logged-in user outside a topic are filtered. Anonymous searches are not:
  # unlike topic lists, `default_tags_muted` and `default_categories_muted` are not applied to them.
  # On a login_required site the only anonymous searches are internal ones, such as discourse-ai's
  # search tool, which should not silently lose those topics. The same goes for the users,
  # categories and tags sections below.
  module SearchExtension
    def apply_filters(posts)
      filtered = super

      user = guardian.user
      if !SiteSetting.mute_enhancements_enabled || !user || @search_context.is_a?(Topic)
        return filtered
      end

      mute_enhancements_filters(user).reduce(filtered) { |result, filter| filter.apply(result) }
    end

    private

    # The users, categories and tags sections of the results (header search and the full page
    # search's "users" and "categories/tags" types) leave out what the user muted or ignored,
    # with no exceptions. Each section builds its query from the model class, so a scope on the
    # class reaches it without copying core's query.

    def user_search
      ids = mute_enhancements_hidden_ids(:user_ids)
      return super() if ids.blank?
      User.where.not(id: ids).scoping { super() }
    end

    def category_search
      ids = mute_enhancements_hidden_ids(:category_ids)
      return super() if ids.blank?

      # User#secure_category_ids queries Category and Guardian memoizes the result, so load it
      # before the scope is on, or it would leave out muted read-restricted categories for the
      # rest of the request.
      secure_category_ids
      Category.where.not(id: ids).scoping { super() }
    end

    def tags_search
      ids = mute_enhancements_hidden_ids(:tag_ids)
      return super() if ids.blank?
      # Tag.visible merges a relation with its own condition on tags.id, and merge replaces earlier
      # conditions on the same column, so a where.not(id:) would be dropped. A SQL string is kept
      # as it is.
      Tag.where("tags.id NOT IN (?)", ids).scoping { super() }
    end

    def mute_enhancements_hidden_ids(kind)
      user = guardian.user
      return [] if !SiteSetting.mute_enhancements_enabled || !user
      HiddenIds.public_send(kind, user)
    end

    def mute_enhancements_filters(user)
      @mute_enhancements_filters ||=
        begin
          words = SearchTerms.words(clean_term)
          filters = []

          if SiteSetting.mute_enhancements_search_muted_tags && SiteSetting.tagging_enabled
            filters << MutedTagsFilter.new(user:, search_context: @search_context, words:)
          end

          # A search within a category, or with a `category:` or `#category` filter, asks for
          # those categories, so it shows them even if muted. Core's filters set
          # @category_filter_matched while they run (in super), and core relies on the same flag
          # to show categories whose search priority is "ignore".
          if SiteSetting.mute_enhancements_search_muted_categories &&
               !@search_context.is_a?(Category) && !@category_filter_matched
            filters << MutedCategoriesFilter.new(user:)
          end

          if SiteSetting.mute_enhancements_search_muted_topics
            filters << MutedTopicsFilter.new(user:)
          end

          if SiteSetting.mute_enhancements_search_ignored_users ||
               SiteSetting.mute_enhancements_search_muted_users
            filters << IgnoredUsersFilter.new(user:, search_context: @search_context, words:)
          end

          filters
        end
    end
  end
end
