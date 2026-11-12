# frozen_string_literal: true

RSpec.describe Search do
  fab!(:user)
  fab!(:category)
  fab!(:muted_tag) { Fabricate(:tag, name: "muted") }
  fab!(:other_muted_tag) { Fabricate(:tag, name: "othermuted") }
  fab!(:regular_tag) { Fabricate(:tag, name: "regular") }

  # Every topic gets a first post containing "needle".
  fab!(:muted_topic) do
    Fabricate(:topic, title: "Topic with a muted tag", tags: [muted_tag]).tap do |topic|
      Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack")
    end
  end
  fab!(:mixed_topic) do
    Fabricate(
      :topic,
      title: "Topic with a muted and a regular tag",
      tags: [muted_tag, regular_tag],
    ).tap { |topic| Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack") }
  end
  fab!(:both_muted_topic) do
    Fabricate(
      :topic,
      title: "Topic with two muted tags",
      tags: [muted_tag, other_muted_tag],
    ).tap { |topic| Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack") }
  end
  fab!(:regular_topic) do
    Fabricate(:topic, title: "Topic with a regular tag", tags: [regular_tag]).tap do |topic|
      Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack")
    end
  end
  fab!(:untagged_topic) do
    Fabricate(:topic, title: "Topic without any tags").tap do |topic|
      Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack")
    end
  end

  let(:visible_topic_ids) { [regular_topic.id, untagged_topic.id] }
  let(:all_topic_ids) do
    [muted_topic.id, mixed_topic.id, both_muted_topic.id, regular_topic.id, untagged_topic.id]
  end
  let(:posts) { Post.where(topic_id: all_topic_ids).to_a }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.search_tag_filter_enabled = true
    SearchIndexer.enable
    posts.each { |post| SearchIndexer.index(post, force: true) }

    [muted_tag, other_muted_tag].each do |tag|
      TagUser.create!(user: user, tag: tag, notification_level: TagUser.notification_levels[:muted])
    end
  end

  def topic_ids_for(term, guardian: Guardian.new(user), **opts)
    Search.execute(term, guardian: guardian, **opts).posts.map(&:topic_id)
  end

  it "hides topics that have any tag the user muted" do
    expect(topic_ids_for("needle")).to contain_exactly(*visible_topic_ids)
  end

  it "hides them from every kind of topic search" do
    expect(topic_ids_for("needle", search_type: :full_page)).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle", type_filter: "topic")).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle order:latest")).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle order:likes")).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle in:all")).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle in:all-posts")).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("in:first status:open")).to include(*visible_topic_ids)
    expect(topic_ids_for("in:first status:open")).not_to include(muted_topic.id)
  end

  it "hides them from older posts searched after the recent ones" do
    SiteSetting.search_recent_regular_posts_offset_post_id = posts.map(&:id).max + 1

    expect(topic_ids_for("needle")).to contain_exactly(*visible_topic_ids)
  end

  it "does not hide anything for a user without muted tags" do
    expect(topic_ids_for("needle", guardian: Fabricate(:user).guardian)).to contain_exactly(
      *all_topic_ids,
    )
  end

  it "does not hide anything when the plugin is disabled" do
    SiteSetting.search_tag_filter_enabled = false

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "does not hide anything when tagging is disabled" do
    SiteSetting.tagging_enabled = false

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "does not hide anything for anonymous searches, even with default_tags_muted" do
    SiteSetting.default_tags_muted = "muted|othermuted"

    expect(topic_ids_for("needle", guardian: Guardian.new)).to contain_exactly(*all_topic_ids)
  end

  it "also filters callers that use apply_filters on their own query, like discourse-ai" do
    # discourse-ai's semantic search builds its own Post query and runs it through
    # Search#apply_filters (DiscourseAi::Embeddings::SemanticSearch#search_for_topics).
    search = Search.new("needle", guardian: Guardian.new(user))
    semantic_results = Post.joins(:topic).where(topic_id: all_topic_ids, post_number: 1)

    expect(search.apply_filters(semantic_results).map(&:topic_id)).to contain_exactly(
      *visible_topic_ids,
    )
  end

  describe "when the search asks for a muted tag" do
    it "shows that tag for tags: filters, but keeps hiding the other muted tags" do
      expect(topic_ids_for("needle tags:muted")).to contain_exactly(muted_topic.id, mixed_topic.id)
      expect(topic_ids_for("needle tag:MUTED")).to contain_exactly(muted_topic.id, mixed_topic.id)
      expect(topic_ids_for("needle tags:muted,regular")).to contain_exactly(
        muted_topic.id,
        mixed_topic.id,
        regular_topic.id,
      )
      expect(topic_ids_for("needle tags:muted+othermuted")).to contain_exactly(both_muted_topic.id)
    end

    it "shows that tag for # filters" do
      expect(topic_ids_for("needle #muted")).to contain_exactly(muted_topic.id, mixed_topic.id)
    end

    it "resolves tag synonyms" do
      Fabricate(:tag, name: "mutedsynonym", target_tag: muted_tag)

      expect(topic_ids_for("needle tags:mutedsynonym")).to contain_exactly(
        muted_topic.id,
        mixed_topic.id,
      )
    end

    it "shows the tags of a tag group for # filters" do
      Fabricate(:tag_group, name: "mutedgroup", tags: [muted_tag, other_muted_tag])

      expect(topic_ids_for("needle #mutedgroup")).to contain_exactly(
        muted_topic.id,
        mixed_topic.id,
        both_muted_topic.id,
      )
    end

    it "does not treat a # filter as a tag when a category has that slug" do
      muted_category = Fabricate(:category, name: "muted")
      muted_topic.update!(category: muted_category)
      regular_topic.update!(category: muted_category)

      expect(topic_ids_for("needle #muted")).to contain_exactly(regular_topic.id)
    end

    it "shows that tag when searching within it" do
      expect(topic_ids_for("needle", search_context: muted_tag)).to contain_exactly(
        muted_topic.id,
        mixed_topic.id,
      )
    end

    it "keeps hiding muted tags for negative tag filters" do
      expect(topic_ids_for("needle -tags:regular")).to contain_exactly(untagged_topic.id)
    end
  end

  it "keeps hiding muted tags when searching within a category" do
    [muted_topic, regular_topic].each { |topic| topic.update!(category: category) }

    expect(topic_ids_for("needle", search_context: category)).to contain_exactly(regular_topic.id)
  end

  it "does not hide anything when searching within a topic" do
    expect(topic_ids_for("needle", search_context: muted_topic)).to eq([muted_topic.id])
  end

  it "does not hide personal messages" do
    message = Fabricate(:private_message_post, user: user, raw: "A needle in a personal message")
    message.topic.tags = [muted_tag]
    SearchIndexer.index(message, force: true)

    expect(topic_ids_for("needle in:messages")).to eq([message.topic_id])
    expect(topic_ids_for("needle in:all")).to contain_exactly(message.topic_id, *visible_topic_ids)
  end

  describe "when the topic is in a category the user watches" do
    before do
      CategoryUser.set_notification_level_for_category(
        user,
        CategoryUser.notification_levels[:watching],
        category.id,
      )
      muted_topic.update!(category: category)
    end

    it "shows it if the user lets watched categories take precedence over muted tags" do
      user.user_option.update!(watched_precedence_over_muted: true)

      expect(topic_ids_for("needle")).to contain_exactly(muted_topic.id, *visible_topic_ids)
    end

    it "hides it otherwise" do
      user.user_option.update!(watched_precedence_over_muted: false)

      expect(topic_ids_for("needle")).to contain_exactly(*visible_topic_ids)
    end
  end
end
