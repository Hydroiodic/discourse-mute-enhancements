# frozen_string_literal: true

module DiscourseSearchTagFilter
  # Prepended to ::Search. Core runs Search#apply_filters inside Search#posts_query, which every
  # search over posts and topics goes through (header search, full page search, `in:all`,
  # `in:all-posts`, pagination). discourse-ai's semantic search builds its own query and calls
  # Search#apply_filters on it too, so hooking here covers both.
  module SearchExtension
    def apply_filters(posts)
      filtered = super
      return filtered if !MutedTagsFilter.applies?(search_context: @search_context)

      @search_tag_filter ||=
        MutedTagsFilter.new(user: guardian.user, search_context: @search_context, term: clean_term)
      @search_tag_filter.apply(filtered)
    end
  end
end
