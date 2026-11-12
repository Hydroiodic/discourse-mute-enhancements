# frozen_string_literal: true

module DiscourseSearchTagFilter
  # Prepended to ::Search. Core runs Search#apply_filters inside Search#posts_query, which every
  # search over posts and topics goes through (header search, full page search, `in:all`,
  # `in:all-posts`, pagination). discourse-ai's semantic search builds its own query and calls
  # Search#apply_filters on it too, so hooking here covers both.
  #
  # Only searches by a logged-in user outside a topic are filtered. Anonymous searches are not:
  # unlike topic lists, `default_tags_muted` and `default_categories_muted` are not applied to them.
  # On a login_required site the only anonymous searches are internal ones, such as discourse-ai's
  # search tool, which should not silently lose those topics.
  module SearchExtension
    def apply_filters(posts)
      filtered = super

      user = guardian.user
      if !SiteSetting.search_tag_filter_enabled || !user || @search_context.is_a?(Topic)
        return filtered
      end

      search_tag_filters(user).reduce(filtered) { |result, filter| filter.apply(result) }
    end

    private

    def search_tag_filters(user)
      @search_tag_filters ||=
        begin
          words = SearchTerms.words(clean_term)
          filters = []

          if SiteSetting.search_tag_filter_muted_tags && SiteSetting.tagging_enabled
            filters << MutedTagsFilter.new(user:, search_context: @search_context, words:)
          end

          # A search within a category, or with a `category:` or `#category` filter, asks for
          # those categories, so it shows them even if muted. Core's filters set
          # @category_filter_matched while they run (in super), and core relies on the same flag
          # to show categories whose search priority is "ignore".
          if SiteSetting.search_tag_filter_muted_categories && !@search_context.is_a?(Category) &&
               !@category_filter_matched
            filters << MutedCategoriesFilter.new(user:)
          end

          if SiteSetting.search_tag_filter_ignored_users ||
               SiteSetting.search_tag_filter_muted_users
            filters << IgnoredUsersFilter.new(user:, search_context: @search_context, words:)
          end

          filters
        end
    end
  end
end
