# frozen_string_literal: true

module DiscourseSearchTagFilter
  # Hides topics in categories the searching user muted. That includes subcategories that inherit
  # the mute from a parent and, with `mute_all_categories_by_default`, every category the user has
  # not set a level for (CategoryUser.muted_category_ids). As in topic lists, a topic is still
  # shown if:
  #
  # - the user tracks or watches the topic itself;
  # - it has a tag the user watches, when the user lets watched take precedence over muted (the
  #   `watched_precedence_over_muted` user option).
  #
  # Searches that ask for a category (searching within a category, `category:` and `#category`
  # filters) don't use this filter at all; SearchExtension decides that.
  class MutedCategoriesFilter
    def initialize(user:)
      @user = user
    end

    def apply(posts)
      return posts if muted_category_ids.empty?

      sql = +<<~SQL
        topics.category_id IS NULL
        OR topics.category_id NOT IN (:category_ids)
        OR EXISTS (
          SELECT 1
          FROM topic_users search_tag_filter_topic_users
          WHERE search_tag_filter_topic_users.topic_id = topics.id
            AND search_tag_filter_topic_users.user_id = :user_id
            AND search_tag_filter_topic_users.notification_level > :regular
        )
      SQL
      sql << <<~SQL if watched_tag_ids.present?
          OR EXISTS (
            SELECT 1
            FROM topic_tags search_tag_filter_watched_tags
            WHERE search_tag_filter_watched_tags.topic_id = topics.id
              AND search_tag_filter_watched_tags.tag_id IN (:tag_ids)
          )
        SQL

      posts.where(
        "(#{sql})",
        category_ids: muted_category_ids,
        user_id: @user.id,
        regular: TopicUser.notification_levels[:regular],
        tag_ids: watched_tag_ids,
      )
    end

    def muted_category_ids
      @muted_category_ids ||= CategoryUser.muted_category_ids(@user)
    end

    private

    def watched_tag_ids
      @watched_tag_ids ||=
        if @user.user_option&.watched_precedence_over_muted
          TagUser
            .where(user: @user)
            .where("notification_level >= ?", TagUser.notification_levels[:watching])
            .pluck(:tag_id)
        else
          []
        end
    end
  end
end
