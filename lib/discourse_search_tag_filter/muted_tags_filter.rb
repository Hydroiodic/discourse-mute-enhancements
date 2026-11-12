# frozen_string_literal: true

module DiscourseSearchTagFilter
  # Decides which tags to hide from one search and adds the matching condition to the posts query.
  #
  # A topic with any tag the searching user muted is hidden, except:
  #
  # - tags the search explicitly asks for: the tag being searched in (search context), positive
  #   `tags:`/`tag:` filters, and `#tag` / `#tag-group` filters;
  # - topics in a category the user watches, when the user lets watched take precedence over
  #   muted (the `watched_precedence_over_muted` user option), as in topic lists;
  # - personal messages.
  #
  # Anonymous searches are not filtered. Unlike topic lists, `default_tags_muted` is not applied
  # to them: on a login_required site the only anonymous searches are internal ones, such as
  # discourse-ai's search tool, which should not silently lose those topics.
  class MutedTagsFilter
    # Copies of the matchers of the `tags:` and `#` advanced filters in core's lib/search.rb.
    TAGS_FILTER = /\Atags?:([\p{L}\p{M}0-9,\-_+]+)\z/i
    HASH_FILTER = /\A\#([\p{L}\p{M}0-9\-:=]+)\z/i

    # Same tokenizer as Search#process_advanced_search!.
    WORD_SCANNER = /(([^" \t\n\x0B\f\r]+)?(("[^"]+")?))/

    def self.applies?(search_context:)
      SiteSetting.search_tag_filter_enabled && SiteSetting.tagging_enabled &&
        !search_context.is_a?(Topic)
    end

    def initialize(user:, search_context:, term:)
      @user = user
      @search_context = search_context
      @term = term
    end

    def apply(posts)
      return posts if hidden_tag_ids.empty?

      sql = +<<~SQL
        topics.archetype = :private_message
        OR NOT EXISTS (
          SELECT 1
          FROM topic_tags search_tag_filter_topic_tags
          WHERE search_tag_filter_topic_tags.topic_id = topics.id
            AND search_tag_filter_topic_tags.tag_id IN (:tag_ids)
        )
      SQL
      sql << "OR topics.category_id IN (:category_ids)" if watched_category_ids.present?

      posts.where(
        "(#{sql})",
        private_message: Archetype.private_message,
        tag_ids: hidden_tag_ids,
        category_ids: watched_category_ids,
      )
    end

    def hidden_tag_ids
      @hidden_tag_ids ||=
        begin
          muted = muted_tag_ids
          muted.empty? ? [] : muted - requested_tag_ids
        end
    end

    private

    def muted_tag_ids
      @user ? TagUser.lookup(@user, :muted).pluck(:tag_id) : []
    end

    def watched_category_ids
      @watched_category_ids ||=
        if @user&.user_option&.watched_precedence_over_muted
          CategoryUser
            .where(user: @user)
            .where("notification_level >= ?", CategoryUser.notification_levels[:watching])
            .pluck(:category_id)
        else
          []
        end
    end

    def requested_tag_ids
      ids = []
      ids << (@search_context.target_tag_id || @search_context.id) if @search_context.is_a?(Tag)

      tag_names = []
      words.each do |word|
        if (match = TAGS_FILTER.match(word))
          tag_names.concat(match[1].split(match[1].include?("+") ? "+" : ","))
        elsif (match = HASH_FILTER.match(word))
          ids.concat(hashtag_tag_ids(match[1]))
        end
      end
      ids.concat(target_tag_ids(Tag.where_name(tag_names))) if tag_names.present?

      ids
    end

    # Mirrors the `#` advanced filter: a category wins, then a tag, then a tag group.
    def hashtag_tag_ids(match)
      category_slug, subcategory_slug = match.split(":")
      return [] if category_slug.blank?

      category_slug = category_slug.delete_prefix("=")
      return [] if category_exists?(category_slug, subcategory_slug)

      tag_ids = target_tag_ids(Tag.where_name(category_slug))
      return tag_ids if tag_ids.present?

      tag_group_id = TagGroup.find_id_by_slug(category_slug)
      tag_group_id ? TagGroupMembership.where(tag_group_id: tag_group_id).pluck(:tag_id) : []
    end

    def category_exists?(slug, subcategory_slug)
      scope =
        if subcategory_slug
          categories_by_slug(subcategory_slug).where(
            parent_category_id: categories_by_slug(slug).select(:id),
          )
        else
          categories_by_slug(slug)
        end
      scope.exists?
    end

    def categories_by_slug(slug)
      Category.where("#{Category.normalize_sql("slug")} = #{Category.normalize_sql("?")}", slug)
    end

    # Topics are tagged with the target of a synonym, never with the synonym itself.
    def target_tag_ids(tags)
      tags.pluck(:id, :target_tag_id).map { |id, target_tag_id| target_tag_id || id }
    end

    def words
      @term.to_s.scan(WORD_SCANNER).filter_map { |(word, _)| word.presence&.gsub(/["']/, "") }
    end
  end
end
