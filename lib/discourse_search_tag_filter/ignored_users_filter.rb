# frozen_string_literal: true

module DiscourseSearchTagFilter
  # Hides what users the searching user ignored wrote: their posts, and topics they started (a
  # result shows the topic title, even when someone else's reply is what matched). With
  # `search_tag_filter_muted_users`, users the searching user muted are hidden the same way. Staff
  # are never hidden, as in topics (IgnoredUser.ignored_ids_for).
  #
  # Not hidden:
  #
  # - users the search explicitly asks for: searching within a user's activity (search context),
  #   `@username` and `user:` filters;
  # - personal messages.
  class IgnoredUsersFilter
    # Copies of the matchers of the `user:` and `@` advanced filters in core's lib/search.rb.
    USER_FILTER = /\Auser:(.+)\z/i
    AT_FILTER = /\A\@(\S+)\z/i

    def initialize(user:, search_context:, words:)
      @user = user
      @search_context = search_context
      @words = words
    end

    def apply(posts)
      return posts if hidden_user_ids.empty?

      posts.where(<<~SQL, private_message: Archetype.private_message, user_ids: hidden_user_ids)
        (
          topics.archetype = :private_message
          OR (
            (posts.user_id IS NULL OR posts.user_id NOT IN (:user_ids))
            AND (topics.user_id IS NULL OR topics.user_id NOT IN (:user_ids))
          )
        )
      SQL
    end

    def hidden_user_ids
      @hidden_user_ids ||=
        begin
          ids = []
          if SiteSetting.search_tag_filter_ignored_users
            ids.concat(IgnoredUser.ignored_ids_for(@user))
          end
          ids.concat(muted_user_ids) if SiteSetting.search_tag_filter_muted_users
          ids.empty? ? [] : ids.uniq - requested_user_ids
        end
    end

    private

    # Same exclusions as IgnoredUser.ignored_ids_for: never the user themselves or staff.
    def muted_user_ids
      User
        .where(id: MutedUser.where(user_id: @user.id).select(:muted_user_id))
        .where(admin: false, moderator: false)
        .where.not(id: @user.id)
        .pluck(:id)
    end

    def requested_user_ids
      ids = []
      ids << @search_context.id if @search_context.is_a?(User)

      @words.each do |word|
        if (match = USER_FILTER.match(word))
          ids.concat(
            User
              .where(staged: false)
              .where("username_lower = ? OR id = ?", match[1].downcase, match[1].to_i)
              .pluck(:id),
          )
        elsif (match = AT_FILTER.match(word))
          ids.concat(
            User.not_staged.where(username_lower: User.normalize_username(match[1])).pluck(:id),
          )
        end
      end

      ids
    end
  end
end
