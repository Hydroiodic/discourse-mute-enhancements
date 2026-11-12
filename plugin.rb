# frozen_string_literal: true

# name: discourse-search-tag-filter
# about: Hide topics with muted tags or categories, and posts by ignored users, from search results.
# version: 0.2
# authors: Hydroiodic

enabled_site_setting :search_tag_filter_enabled

module ::DiscourseSearchTagFilter
  PLUGIN_NAME = "discourse-search-tag-filter"
end

require_relative "lib/discourse_search_tag_filter/search_terms"
require_relative "lib/discourse_search_tag_filter/muted_tags_filter"
require_relative "lib/discourse_search_tag_filter/muted_categories_filter"
require_relative "lib/discourse_search_tag_filter/ignored_users_filter"
require_relative "lib/discourse_search_tag_filter/search_extension"

after_initialize do
  reloadable_patch { ::Search.prepend(DiscourseSearchTagFilter::SearchExtension) }
end
