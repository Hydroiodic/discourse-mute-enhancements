# frozen_string_literal: true

# The users, categories and tags sections of search results.
RSpec.describe Search do
  fab!(:user)
  fab!(:ignored_user) { Fabricate(:user, username: "needleignored") }
  fab!(:muted_user) { Fabricate(:user, username: "needlemuted") }
  fab!(:other_user) { Fabricate(:user, username: "needleother") }
  fab!(:muted_moderator) { Fabricate(:moderator, username: "needlemoderator") }
  fab!(:muted_category) { Fabricate(:category, name: "Needle muted category") }
  fab!(:muted_subcategory) do
    Fabricate(:category, name: "Needle muted subcategory", parent_category: muted_category)
  end
  fab!(:regular_category) { Fabricate(:category, name: "Needle regular category") }
  fab!(:muted_tag) { Fabricate(:tag, name: "needle-muted") }
  fab!(:regular_tag) { Fabricate(:tag, name: "needle-regular") }

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.mute_enhancements_enabled = true
    SearchIndexer.enable
    [
      ignored_user,
      muted_user,
      other_user,
      muted_moderator,
      muted_category,
      muted_subcategory,
      regular_category,
      muted_tag,
      regular_tag,
    ].each { |record| SearchIndexer.index(record, force: true) }

    IgnoredUser.create!(user:, ignored_user:, expiring_at: 1.month.from_now)
    MutedUser.create!(user:, muted_user:)
    MutedUser.create!(user:, muted_user: muted_moderator)
    CategoryUser.set_notification_level_for_category(
      user,
      CategoryUser.notification_levels[:muted],
      muted_category.id,
    )
    TagUser.create!(user:, tag: muted_tag, notification_level: TagUser.notification_levels[:muted])
  end

  def search(searcher: user, **opts)
    Search.execute("needle", guardian: Guardian.new(searcher), **opts)
  end

  def user_ids(result) = result.users.map(&:id)
  def category_ids(result) = result.categories.map(&:id)
  def tag_ids(result) = result.tags.map(&:id)

  it "leaves out ignored and muted users, but not staff" do
    expect(user_ids(search)).to contain_exactly(other_user.id, muted_moderator.id)
  end

  it "leaves out muted categories and their subcategories" do
    expect(category_ids(search)).to contain_exactly(regular_category.id)
  end

  it "leaves out muted tags" do
    expect(tag_ids(search)).to contain_exactly(regular_tag.id)
  end

  it "does the same in the header search" do
    result = search(search_type: :header)

    expect(user_ids(result)).to contain_exactly(other_user.id, muted_moderator.id)
    expect(category_ids(result)).to contain_exactly(regular_category.id)
    expect(tag_ids(result)).to contain_exactly(regular_tag.id)
  end

  it "does the same when searching one type" do
    expect(user_ids(search(type_filter: "user"))).to contain_exactly(
      other_user.id,
      muted_moderator.id,
    )
    expect(category_ids(search(type_filter: "category"))).to contain_exactly(regular_category.id)
    expect(tag_ids(search(type_filter: "tags"))).to contain_exactly(regular_tag.id)

    result = search(type_filter: "exclude_topics")
    expect(user_ids(result)).to contain_exactly(other_user.id, muted_moderator.id)
    expect(category_ids(result)).to contain_exactly(regular_category.id)
    expect(tag_ids(result)).to contain_exactly(regular_tag.id)
  end

  it "follows each setting" do
    SiteSetting.mute_enhancements_search_ignored_users = false
    expect(user_ids(search)).to contain_exactly(ignored_user.id, other_user.id, muted_moderator.id)

    SiteSetting.mute_enhancements_search_muted_users = false
    expect(user_ids(search)).to contain_exactly(
      ignored_user.id,
      muted_user.id,
      other_user.id,
      muted_moderator.id,
    )

    SiteSetting.mute_enhancements_search_muted_categories = false
    expect(category_ids(search)).to contain_exactly(
      muted_category.id,
      muted_subcategory.id,
      regular_category.id,
    )

    SiteSetting.mute_enhancements_search_muted_tags = false
    expect(tag_ids(search)).to contain_exactly(muted_tag.id, regular_tag.id)
  end

  it "leaves everything in when the plugin is disabled" do
    SiteSetting.mute_enhancements_enabled = false
    result = search

    expect(user_ids(result)).to include(ignored_user.id, muted_user.id)
    expect(category_ids(result)).to include(muted_category.id, muted_subcategory.id)
    expect(tag_ids(result)).to include(muted_tag.id)
  end

  it "does not filter anonymous searches" do
    result = search(searcher: nil)

    expect(user_ids(result)).to include(ignored_user.id, muted_user.id)
    expect(category_ids(result)).to include(muted_category.id)
    expect(tag_ids(result)).to include(muted_tag.id)
  end

  it "only hides categories for the searching user" do
    result = search(searcher: Fabricate(:user))
    expect(category_ids(result)).to include(muted_category.id, muted_subcategory.id)
  end

  context "with a muted read-restricted category" do
    fab!(:group)
    fab!(:secure_category) do
      Fabricate(:private_category, name: "Needle secure category", group: group)
    end
    fab!(:secure_post) do
      Fabricate(
        :post,
        topic: Fabricate(:topic, category: secure_category),
        raw: "Looking for a needle in a secure topic",
      )
    end

    before do
      group.add(user)
      SearchIndexer.index(secure_category, force: true)
      SearchIndexer.index(secure_post, force: true)
      CategoryUser.set_notification_level_for_category(
        user,
        CategoryUser.notification_levels[:muted],
        secure_category.id,
      )
    end

    it "hides the category without losing access to it for the rest of the search" do
      guardian = Guardian.new(user)
      result =
        Search.execute("needle ##{secure_category.slug}", guardian: guardian, type_filter: "topic")

      expect(guardian.secure_category_ids).to include(secure_category.id)
      expect(result.posts.map(&:id)).to contain_exactly(secure_post.id)

      expect(category_ids(search)).not_to include(secure_category.id)
    end
  end
end
