# frozen_string_literal: true

# The lookups behind the search box's `@` and `#` suggestions and the full page search's "users"
# and "categories/tags" types. The browser marks the lookups made from search with
# mute_enhancements_search.
RSpec.describe "Search suggestions" do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:ignored_user) { Fabricate(:user, username: "needleignored") }
  fab!(:muted_user) { Fabricate(:user, username: "needlemuted") }
  fab!(:other_user) { Fabricate(:user, username: "needleother") }
  fab!(:muted_moderator) { Fabricate(:moderator, username: "needlemoderator") }

  let(:everyone) { %w[needleignored needlemuted needleother needlemoderator] }

  before do
    SiteSetting.mute_enhancements_enabled = true
    IgnoredUser.create!(user:, ignored_user:, expiring_at: 1.month.from_now)
    MutedUser.create!(user:, muted_user:)
    MutedUser.create!(user:, muted_user: muted_moderator)
    sign_in(user)
  end

  describe "users" do
    before do
      SearchIndexer.enable
      [ignored_user, muted_user, other_user, muted_moderator].each do |u|
        SearchIndexer.index(u, force: true)
      end
    end

    def usernames(**params)
      get "/u/search/users.json", params: { include_groups: true, limit: 6, **params }
      expect(response.status).to eq(200)
      response.parsed_body["users"].map { |found| found["username"] }
    end

    it "leaves out ignored and muted users, but not staff, when searching" do
      expect(usernames(term: "needle", mute_enhancements_search: true)).to contain_exactly(
        "needleother",
        "needlemoderator",
      )
    end

    it "still lists them for other lookups, such as mentions" do
      expect(usernames(term: "needle")).to match_array(everyone)
      expect(usernames(term: "needle", mute_enhancements_search: false)).to match_array(everyone)
    end

    it "leaves them out of the recently seen users suggested after a bare @" do
      [ignored_user, muted_user, other_user].each { |u| u.update!(last_seen_at: 1.minute.ago) }

      found = usernames(term: "", last_seen_users: true, mute_enhancements_search: true)
      expect(found).to include("needleother")
      expect(found).not_to include("needleignored", "needlemuted")
    end

    it "follows the settings" do
      SiteSetting.mute_enhancements_search_muted_users = false
      expect(usernames(term: "needle", mute_enhancements_search: true)).to contain_exactly(
        "needlemuted",
        "needleother",
        "needlemoderator",
      )

      SiteSetting.mute_enhancements_enabled = false
      expect(usernames(term: "needle", mute_enhancements_search: true)).to match_array(everyone)
    end
  end

  describe "tags" do
    fab!(:muted_tag) { Fabricate(:tag, name: "needle-muted") }
    fab!(:regular_tag) { Fabricate(:tag, name: "needle-regular") }

    before do
      SiteSetting.tagging_enabled = true
      TagUser.create!(
        user:,
        tag: muted_tag,
        notification_level: TagUser.notification_levels[:muted],
      )
    end

    def tag_names(**params)
      get "/tags/filter/search.json", params: { q: "needle", limit: 5, **params }
      expect(response.status).to eq(200)
      response.parsed_body["results"].map { |tag| tag["name"] }
    end

    it "leaves out muted tags when searching" do
      expect(tag_names(mute_enhancements_search: true)).to contain_exactly("needle-regular")
    end

    it "still lists them for other lookups and for tag choosers" do
      expect(tag_names).to contain_exactly("needle-muted", "needle-regular")
      expect(tag_names(mute_enhancements_search: true, filterForInput: true)).to contain_exactly(
        "needle-muted",
        "needle-regular",
      )
    end

    it "still leaves out the selected tags" do
      expect(
        tag_names(mute_enhancements_search: true, selected_tag_ids: [regular_tag.id]),
      ).to be_empty
    end

    it "follows the settings" do
      SiteSetting.mute_enhancements_search_muted_tags = false
      expect(tag_names(mute_enhancements_search: true)).to contain_exactly(
        "needle-muted",
        "needle-regular",
      )
    end
  end

  describe "categories muted by default" do
    fab!(:unset_category, :category)
    fab!(:regular_category, :category)
    fab!(:muted_category, :category)

    before do
      CategoryUser.set_notification_level_for_category(
        user,
        CategoryUser.notification_levels[:regular],
        regular_category.id,
      )
      CategoryUser.set_notification_level_for_category(
        user,
        CategoryUser.notification_levels[:muted],
        muted_category.id,
      )
    end

    def current_user_json
      get "/session/current.json"
      expect(response.status).to eq(200)
      response.parsed_body["current_user"]
    end

    it "sends the categories muted only by mute_all_categories_by_default" do
      SiteSetting.mute_all_categories_by_default = true

      json = current_user_json
      expect(json["mute_enhancements_default_muted_category_ids"]).to include(unset_category.id)
      expect(json["mute_enhancements_default_muted_category_ids"]).not_to include(
        regular_category.id,
        muted_category.id,
      )
      expect(json["muted_category_ids"]).to include(muted_category.id)
    end

    it "sends none without mute_all_categories_by_default" do
      expect(current_user_json["mute_enhancements_default_muted_category_ids"]).to eq([])
    end

    it "is left out when the search does not hide muted categories" do
      SiteSetting.mute_enhancements_search_muted_categories = false
      expect(current_user_json).not_to have_key("mute_enhancements_default_muted_category_ids")
    end
  end
end
