# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Hides topics the searching user muted (topic notification level Muted), including topics muted
  # for them by a group (GroupMutedTopics). Personal messages are not hidden, like everywhere else
  # in search.
  #
  # Searching within the topic, including with a `topic:` filter, which makes the topic the search
  # context, doesn't use this filter at all; SearchExtension decides that.
  class MutedTopicsFilter
    def initialize(user:)
      @user = user
    end

    def apply(posts)
      posts.where(<<~SQL, private_message: Archetype.private_message, user_id: @user.id, muted:)
        (
          topics.archetype = :private_message
          OR NOT EXISTS (
            SELECT 1
            FROM topic_users mute_enhancements_muted_topics
            WHERE mute_enhancements_muted_topics.topic_id = topics.id
              AND mute_enhancements_muted_topics.user_id = :user_id
              AND mute_enhancements_muted_topics.notification_level = :muted
          )
        )
      SQL
    end

    private

    def muted
      TopicUser.notification_levels[:muted]
    end
  end
end
