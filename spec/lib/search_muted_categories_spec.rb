# frozen_string_literal: true

RSpec.describe Search do
  fab!(:user)
  fab!(:muted_category) { Fabricate(:category, name: "Muted category", slug: "muted-category") }
  fab!(:muted_subcategory) do
    Fabricate(
      :category,
      name: "Muted subcategory",
      slug: "muted-subcategory",
      parent_category: muted_category,
    )
  end
  fab!(:regular_category) do
    Fabricate(:category, name: "Regular category", slug: "regular-category")
  end

  # Every topic gets a first post containing "needle".
  fab!(:muted_topic) do
    Fabricate(:topic, title: "Topic in a muted category", category: muted_category).tap do |topic|
      Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack")
    end
  end
  fab!(:subcategory_topic) do
    Fabricate(
      :topic,
      title: "Topic in a subcategory of a muted category",
      category: muted_subcategory,
    ).tap { |topic| Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack") }
  end
  fab!(:regular_topic) do
    Fabricate(
      :topic,
      title: "Topic in a regular category",
      category: regular_category,
    ).tap { |topic| Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack") }
  end
  fab!(:uncategorized_topic) do
    Fabricate(:topic, title: "Topic without a category").tap do |topic|
      Fabricate(:post, topic: topic, raw: "Looking for a needle in a haystack")
    end
  end

  let(:visible_topic_ids) { [regular_topic.id, uncategorized_topic.id] }
  let(:all_topic_ids) do
    [muted_topic.id, subcategory_topic.id, regular_topic.id, uncategorized_topic.id]
  end

  before do
    SiteSetting.search_tag_filter_enabled = true
    SearchIndexer.enable
    Post.where(topic_id: all_topic_ids).each { |post| SearchIndexer.index(post, force: true) }

    CategoryUser.set_notification_level_for_category(
      user,
      CategoryUser.notification_levels[:muted],
      muted_category.id,
    )
  end

  def topic_ids_for(term, guardian: Guardian.new(user), **opts)
    Search.execute(term, guardian: guardian, **opts).posts.map(&:topic_id)
  end

  it "hides topics in muted categories and in their subcategories" do
    expect(topic_ids_for("needle")).to contain_exactly(*visible_topic_ids)
  end

  it "hides them from every kind of topic search" do
    expect(topic_ids_for("needle", search_type: :full_page)).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle", type_filter: "topic")).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle order:latest")).to contain_exactly(*visible_topic_ids)
    expect(topic_ids_for("needle in:all-posts")).to contain_exactly(*visible_topic_ids)
  end

  it "hides a subcategory the user muted on its own" do
    CategoryUser.set_notification_level_for_category(
      user,
      CategoryUser.notification_levels[:regular],
      muted_category.id,
    )
    CategoryUser.set_notification_level_for_category(
      user,
      CategoryUser.notification_levels[:muted],
      muted_subcategory.id,
    )

    expect(topic_ids_for("needle")).to contain_exactly(muted_topic.id, *visible_topic_ids)
  end

  it "hides every category the user has not set a level for, with mute_all_categories_by_default" do
    SiteSetting.mute_all_categories_by_default = true
    CategoryUser.set_notification_level_for_category(
      user,
      CategoryUser.notification_levels[:regular],
      regular_category.id,
    )

    expect(topic_ids_for("needle")).to contain_exactly(regular_topic.id)
  end

  it "does not hide anything when muted categories are not filtered" do
    SiteSetting.search_tag_filter_muted_categories = false

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "does not hide anything when the plugin is disabled" do
    SiteSetting.search_tag_filter_enabled = false

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "does not hide anything for anonymous searches, even with default_categories_muted" do
    SiteSetting.default_categories_muted = muted_category.id.to_s

    expect(topic_ids_for("needle", guardian: Guardian.new)).to contain_exactly(*all_topic_ids)
  end

  it "also filters callers that use apply_filters on their own query, like discourse-ai" do
    search = Search.new("needle", guardian: Guardian.new(user))
    semantic_results = Post.joins(:topic).where(topic_id: all_topic_ids, post_number: 1)

    expect(search.apply_filters(semantic_results).map(&:topic_id)).to contain_exactly(
      *visible_topic_ids,
    )
  end

  describe "when the search asks for a muted category" do
    it "shows it when searching within it" do
      expect(topic_ids_for("needle", search_context: muted_category)).to contain_exactly(
        muted_topic.id,
        subcategory_topic.id,
      )
    end

    it "shows it for # filters" do
      expect(topic_ids_for("needle #muted-category")).to contain_exactly(
        muted_topic.id,
        subcategory_topic.id,
      )
      expect(topic_ids_for("needle #=muted-category")).to contain_exactly(muted_topic.id)
      expect(topic_ids_for("needle #muted-category:muted-subcategory")).to contain_exactly(
        subcategory_topic.id,
      )
    end

    it "shows it for category: filters" do
      expect(topic_ids_for("needle category:muted-category")).to contain_exactly(
        muted_topic.id,
        subcategory_topic.id,
      )
      expect(
        topic_ids_for("needle categories:=muted-category,regular-category"),
      ).to contain_exactly(muted_topic.id, regular_topic.id)
    end

    it "keeps hiding it for a # filter that matches a tag" do
      SiteSetting.tagging_enabled = true
      tag = Fabricate(:tag, name: "sometag")
      [muted_topic, regular_topic].each { |topic| topic.update!(tags: [tag]) }

      expect(topic_ids_for("needle #sometag")).to contain_exactly(regular_topic.id)
    end
  end

  it "shows topics the user tracks or watches" do
    TopicUser.change(
      user.id,
      muted_topic.id,
      notification_level: TopicUser.notification_levels[:tracking],
    )
    TopicUser.change(
      user.id,
      subcategory_topic.id,
      notification_level: TopicUser.notification_levels[:watching],
    )

    expect(topic_ids_for("needle")).to contain_exactly(*all_topic_ids)
  end

  it "keeps hiding topics the user has a regular level for" do
    TopicUser.change(
      user.id,
      muted_topic.id,
      notification_level: TopicUser.notification_levels[:regular],
    )

    expect(topic_ids_for("needle")).to contain_exactly(*visible_topic_ids)
  end

  describe "when the topic has a tag the user watches" do
    fab!(:watched_tag) { Fabricate(:tag, name: "watched") }

    before do
      SiteSetting.tagging_enabled = true
      muted_topic.update!(tags: [watched_tag])
      TagUser.create!(
        user: user,
        tag: watched_tag,
        notification_level: TagUser.notification_levels[:watching],
      )
    end

    it "shows it if the user lets watched tags take precedence over muted categories" do
      user.user_option.update!(watched_precedence_over_muted: true)

      expect(topic_ids_for("needle")).to contain_exactly(muted_topic.id, *visible_topic_ids)
    end

    it "hides it otherwise" do
      user.user_option.update!(watched_precedence_over_muted: false)

      expect(topic_ids_for("needle")).to contain_exactly(*visible_topic_ids)
    end
  end
end
