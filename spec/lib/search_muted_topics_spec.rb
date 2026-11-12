# frozen_string_literal: true

RSpec.describe Search do
  fab!(:user)
  fab!(:other_user, :user)

  # Every topic gets a first post containing "needle".
  fab!(:muted_topic) do
    Fabricate(:topic, title: "Topic the user muted").tap do |topic|
      Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack")
    end
  end
  fab!(:regular_topic) do
    Fabricate(:topic, title: "Topic the user did not mute").tap do |topic|
      Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack")
    end
  end
  fab!(:reply) { Fabricate(:post, topic: muted_topic, raw: "A reply with another needle") }

  let(:all_topic_ids) { [muted_topic.id, regular_topic.id] }

  before do
    SiteSetting.mute_enhancements_enabled = true
    SearchIndexer.enable
    Post.where(topic_id: all_topic_ids).each { |post| SearchIndexer.index(post, force: true) }

    TopicUser.change(user, muted_topic, notification_level: TopicUser.notification_levels[:muted])
  end

  def topic_ids_for(term, guardian: Guardian.new(user), **opts)
    Search.execute(term, guardian: guardian, **opts).posts.map(&:topic_id)
  end

  it "hides topics the user muted, replies included" do
    expect(topic_ids_for("needle")).to contain_exactly(regular_topic.id)
    expect(topic_ids_for("another")).to be_empty
  end

  it "hides them from every kind of topic search" do
    expect(topic_ids_for("needle", search_type: :full_page)).to contain_exactly(regular_topic.id)
    expect(topic_ids_for("needle", type_filter: "topic")).to contain_exactly(regular_topic.id)
    expect(topic_ids_for("needle order:latest")).to contain_exactly(regular_topic.id)
    expect(topic_ids_for("needle in:all-posts")).to contain_exactly(regular_topic.id)
  end

  it "hides topics muted for the user by a group" do
    group = Fabricate(:group)
    group.add(user)
    DiscourseMuteEnhancements::GroupMutedTopics.update(group, regular_topic.id.to_s)

    expect(topic_ids_for("needle")).to be_empty
  end

  it "shows a topic again when the user changes its level back" do
    TopicUser.change(user, muted_topic, notification_level: TopicUser.notification_levels[:regular])

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "only hides them for the user who muted them" do
    expect(topic_ids_for("needle", guardian: Guardian.new(other_user))).to contain_exactly(
      *all_topic_ids,
    )
  end

  it "shows them when searching within the topic, including with topic:" do
    expect(topic_ids_for("needle", search_context: muted_topic).uniq).to eq([muted_topic.id])
    expect(topic_ids_for("needle topic:#{muted_topic.id}")).to include(muted_topic.id)
  end

  it "still finds the topic by its id or link" do
    # As the header search sends them.
    opts = { search_for_id: true, type_filter: "topic" }
    expect(topic_ids_for(muted_topic.id.to_s, **opts)).to eq([muted_topic.id])
    expect(topic_ids_for(muted_topic.url, **opts)).to eq([muted_topic.id])
  end

  it "does not hide personal messages the user muted" do
    message = Fabricate(:private_message_topic, user: other_user, recipient: user)
    Fabricate(:post, topic: message, user: other_user, raw: "A message with a needle").tap do |post|
      SearchIndexer.index(post, force: true)
    end
    TopicUser.change(user, message, notification_level: TopicUser.notification_levels[:muted])

    expect(topic_ids_for("needle in:messages")).to contain_exactly(message.id)
  end

  it "also filters callers that use apply_filters on their own query, like discourse-ai" do
    search = Search.new("needle", guardian: Guardian.new(user))
    semantic_results = Post.joins(:topic).where(topic_id: all_topic_ids, post_number: 1)

    expect(search.apply_filters(semantic_results).map(&:topic_id)).to contain_exactly(
      regular_topic.id,
    )
  end

  it "does not hide anything when muted topics are not filtered" do
    SiteSetting.mute_enhancements_search_muted_topics = false

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "does not hide anything when the plugin is disabled" do
    SiteSetting.mute_enhancements_enabled = false

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "does not hide anything for anonymous searches" do
    expect(topic_ids_for("needle", guardian: Guardian.new)).to contain_exactly(*all_topic_ids)
  end
end
