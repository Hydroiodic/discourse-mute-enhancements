# frozen_string_literal: true

RSpec.describe Search do
  fab!(:user)
  fab!(:ignored_user) { Fabricate(:user, username: "ignoreduser") }
  fab!(:muted_user) { Fabricate(:user, username: "muteduser") }
  fab!(:other_user) { Fabricate(:user, username: "otheruser") }

  # Each topic has a first post without the needle and one reply with it, so the reply is the only
  # result the topic can give.
  fab!(:ignored_reply) do
    topic = Fabricate(:topic, user: other_user, title: "Topic with a reply by an ignored user")
    Fabricate(:post, topic: topic, user: other_user, raw: "This first post has nothing to find")
    Fabricate(:post, topic: topic, user: ignored_user, raw: "Looking for a needle in a haystack")
  end
  fab!(:reply_in_ignored_topic) do
    topic = Fabricate(:topic, user: ignored_user, title: "Topic started by an ignored user")
    Fabricate(:post, topic: topic, user: ignored_user, raw: "This first post has nothing to find")
    Fabricate(:post, topic: topic, user: other_user, raw: "Looking for a needle in a haystack")
  end
  fab!(:muted_reply) do
    topic = Fabricate(:topic, user: other_user, title: "Topic with a reply by a muted user")
    Fabricate(:post, topic: topic, user: other_user, raw: "This first post has nothing to find")
    Fabricate(:post, topic: topic, user: muted_user, raw: "Looking for a needle in a haystack")
  end
  fab!(:regular_reply) do
    topic = Fabricate(:topic, user: other_user, title: "Topic with a reply by another user")
    Fabricate(:post, topic: topic, user: other_user, raw: "This first post has nothing to find")
    Fabricate(:post, topic: topic, user: other_user, raw: "Looking for a needle in a haystack")
  end

  let(:replies) { [ignored_reply, reply_in_ignored_topic, muted_reply, regular_reply] }

  before do
    SiteSetting.search_tag_filter_enabled = true
    SearchIndexer.enable
    Post
      .where(topic_id: replies.map(&:topic_id))
      .each { |post| SearchIndexer.index(post, force: true) }

    Fabricate(:ignored_user, user: user, ignored_user: ignored_user)
    Fabricate(:muted_user, user: user, muted_user: muted_user)
  end

  def post_ids_for(term, guardian: Guardian.new(user), **opts)
    Search.execute(term, guardian: guardian, **opts).posts.map(&:id)
  end

  it "hides posts by ignored users and topics they started" do
    expect(post_ids_for("needle")).to contain_exactly(muted_reply.id, regular_reply.id)
  end

  it "hides them from every kind of topic search" do
    expect(post_ids_for("needle", search_type: :full_page)).to contain_exactly(
      muted_reply.id,
      regular_reply.id,
    )
    expect(post_ids_for("needle", type_filter: "topic")).to contain_exactly(
      muted_reply.id,
      regular_reply.id,
    )
    expect(post_ids_for("needle in:all-posts")).to contain_exactly(muted_reply.id, regular_reply.id)
  end

  it "hides muted users too when search_tag_filter_muted_users is enabled" do
    SiteSetting.search_tag_filter_muted_users = true

    expect(post_ids_for("needle")).to contain_exactly(regular_reply.id)
  end

  it "only hides muted users when ignored users are not filtered" do
    SiteSetting.search_tag_filter_ignored_users = false
    SiteSetting.search_tag_filter_muted_users = true

    expect(post_ids_for("needle")).to contain_exactly(
      ignored_reply.id,
      reply_in_ignored_topic.id,
      regular_reply.id,
    )
  end

  it "does not hide anything when ignored users are not filtered" do
    SiteSetting.search_tag_filter_ignored_users = false

    expect(post_ids_for("needle")).to contain_exactly(*replies.map(&:id))
  end

  it "does not hide anything when the plugin is disabled" do
    SiteSetting.search_tag_filter_enabled = false

    expect(post_ids_for("needle")).to contain_exactly(*replies.map(&:id))
  end

  it "does not hide ignored staff" do
    ignored_user.update!(moderator: true)

    expect(post_ids_for("needle")).to contain_exactly(*replies.map(&:id))
  end

  it "keeps posts whose author was deleted" do
    regular_reply.update_columns(user_id: nil)
    regular_reply.topic.update_columns(user_id: nil)

    expect(post_ids_for("needle")).to contain_exactly(muted_reply.id, regular_reply.id)
  end

  it "also filters callers that use apply_filters on their own query, like discourse-ai" do
    search = Search.new("needle", guardian: Guardian.new(user))
    semantic_results = Post.joins(:topic).where(id: replies.map(&:id))

    expect(search.apply_filters(semantic_results).map(&:id)).to contain_exactly(
      muted_reply.id,
      regular_reply.id,
    )
  end

  describe "when the search asks for an ignored user" do
    it "shows them for @ and user: filters" do
      expect(post_ids_for("needle @ignoreduser")).to eq([ignored_reply.id])
      expect(post_ids_for("needle @IgnoredUser")).to eq([ignored_reply.id])
      expect(post_ids_for("needle user:ignoreduser")).to eq([ignored_reply.id])
    end

    it "shows them when searching within their activity" do
      expect(post_ids_for("needle", search_context: ignored_user)).to eq([ignored_reply.id])
    end

    it "keeps hiding topics they started when asking for someone else" do
      expect(post_ids_for("needle @otheruser")).to eq([regular_reply.id])
    end
  end

  it "does not hide personal messages" do
    message =
      Fabricate(
        :private_message_post,
        user: ignored_user,
        recipient: user,
        raw: "A needle in a personal message",
      )
    SearchIndexer.index(message, force: true)

    expect(post_ids_for("needle in:messages")).to eq([message.id])
  end
end
