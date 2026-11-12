# frozen_string_literal: true

RSpec.describe SearchController do
  fab!(:user)
  fab!(:muted_tag) { Fabricate(:tag, name: "muted") }
  fab!(:muted_post) do
    Fabricate(
      :post,
      topic: Fabricate(:topic, title: "Topic with a muted tag", tags: [muted_tag]),
      raw: "Looking for a needle in a muted topic",
    )
  end
  fab!(:regular_post) { Fabricate(:post, raw: "Looking for a needle in a regular topic") }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.search_tag_filter_enabled = true
    SearchIndexer.enable
    [muted_post, regular_post].each { |post| SearchIndexer.index(post, force: true) }
    TagUser.create!(
      user: user,
      tag: muted_tag,
      notification_level: TagUser.notification_levels[:muted],
    )
    sign_in(user)
  end

  def topic_ids
    response.parsed_body["posts"].map { |post| post["topic_id"] }
  end

  it "hides topics with muted tags from the header search" do
    get "/search/query.json", params: { term: "needle" }

    expect(response.status).to eq(200)
    expect(topic_ids).to eq([regular_post.topic_id])
  end

  it "hides topics with muted tags from the full page search" do
    get "/search.json", params: { q: "needle" }

    expect(response.status).to eq(200)
    expect(topic_ids).to eq([regular_post.topic_id])
  end

  it "hides topics in muted categories and posts by ignored users" do
    muted_category = Fabricate(:category)
    muted_category_post =
      Fabricate(
        :post,
        topic: Fabricate(:topic, category: muted_category),
        raw: "Looking for a needle in a muted category",
      )
    CategoryUser.set_notification_level_for_category(
      user,
      CategoryUser.notification_levels[:muted],
      muted_category.id,
    )
    ignored_user_post = Fabricate(:post, raw: "Looking for a needle from an ignored user")
    Fabricate(:ignored_user, user: user, ignored_user: ignored_user_post.user)
    [muted_category_post, ignored_user_post].each { |post| SearchIndexer.index(post, force: true) }

    get "/search/query.json", params: { term: "needle" }

    expect(response.status).to eq(200)
    expect(topic_ids).to eq([regular_post.topic_id])
  end

  it "shows them when searching within the muted tag" do
    get "/search/query.json",
        params: {
          term: "needle",
          search_context: {
            type: "tag",
            id: "muted",
          },
        }

    expect(response.status).to eq(200)
    expect(topic_ids).to eq([muted_post.topic_id])
  end
end
