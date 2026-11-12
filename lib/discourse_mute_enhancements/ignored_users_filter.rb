# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Hides what users the searching user ignored (`mute_enhancements_search_ignored_users`) or
  # muted (`mute_enhancements_search_muted_users`) wrote: their posts, and topics they started (a
  # result shows the topic title, even when someone else's reply is what matched). Staff are
  # never hidden, as in topics (IgnoredUser.ignored_ids_for).
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
          ids = HiddenIds.user_ids(@user)
          ids.empty? ? [] : ids - requested_user_ids
        end
    end

    private

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
