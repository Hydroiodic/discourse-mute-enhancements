# frozen_string_literal: true

RSpec.describe DiscourseMuteEnhancements::GroupHidePreferencesController do
  fab!(:admin)
  fab!(:moderator)
  fab!(:group)
  fab!(:member, :user)
  fab!(:outsider, :user)

  let(:path) { "/mute-enhancements/groups/#{group.id}/hide-preferences.json" }

  before do
    SiteSetting.mute_enhancements_enabled = true
    group.add(member)
  end

  def hidden_pages(user)
    sign_in(user)
    get "/session/current.json"
    response.parsed_body["current_user"]["mute_enhancements_hidden_preferences"]
  end

  def group_pages(target = group) = DiscourseMuteEnhancements::HiddenPreferences.group_pages(target)

  def hide(pages, target = group) =
    DiscourseMuteEnhancements::HiddenPreferences.update(target, pages)

  it "is for admins only" do
    sign_in(moderator)
    put path, params: { hidden_pages: "users" }
    expect(response.status).to eq(403)

    owner = Fabricate(:user)
    group.add_owner(owner)
    sign_in(owner)
    put path, params: { hidden_pages: "users" }
    expect(response.status).to eq(403)

    expect(group_pages).to be_empty
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "sets each page on its own, and logs each change" do
      put path, params: { hidden_pages: "users" }
      expect(response.status).to eq(200)
      expect(response.parsed_body["hidden_preferences"]).to eq(%w[users])

      put path, params: { hidden_pages: "users,tracking" }
      expect(response.parsed_body["hidden_preferences"]).to eq(%w[tracking users])
      expect(group_pages).to eq(%w[tracking users])

      put path, params: { hidden_pages: "tracking,users" }
      expect(response.status).to eq(200)

      put path, params: { hidden_pages: "users,notifications,tracking" }
      expect(response.parsed_body["hidden_preferences"]).to eq(%w[notifications tracking users])

      put path, params: { hidden_pages: "" }
      expect(response.parsed_body["hidden_preferences"]).to eq([])
      expect(GroupCustomField.where(group:, name: "mute_enhancements_hide_preferences")).to be_empty

      logs = UserHistory.where(custom_type: "mute_enhancements_group_hide_preferences").order(:id)
      expect(logs.count).to eq(4)
      expect(logs.map(&:details)).to all(include(group.name))
      expect(logs.second.details).to include("tracking, users")
      expect(logs.third.details).to include("notifications, tracking, users")
    end

    it "rejects unknown pages" do
      put path, params: { hidden_pages: "users,interface" }
      expect(response.status).to eq(400)
      expect(group_pages).to be_empty

      put path
      expect(response.status).to eq(400)
    end

    it "rejects automatic groups" do
      put "/mute-enhancements/groups/#{Group::AUTO_GROUPS[:trust_level_1]}/hide-preferences.json",
          params: {
            hidden_pages: "users",
          }
      expect(response.status).to eq(400)
    end

    it "is not found when the feature is disabled" do
      SiteSetting.mute_enhancements_group_hide_preferences = false
      put path, params: { hidden_pages: "users" }
      expect(response.status).to eq(404)
    end

    it "shows the hidden pages on the group to admins only" do
      hide(%w[users])
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]["mute_enhancements_hidden_preferences"]).to eq(%w[users])

      sign_in(moderator)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_hidden_preferences")
    end
  end

  describe "the current user" do
    it "lists the pages hidden by any of the member's groups" do
      expect(hidden_pages(member)).to be_nil

      hide(%w[users])
      expect(hidden_pages(member)).to eq(%w[users])
      expect(hidden_pages(outsider)).to be_nil

      other = Fabricate(:group)
      other.add(member)
      hide(%w[tracking], other)
      expect(hidden_pages(member)).to eq(%w[tracking users])
    end

    it "leaves admins and moderators alone" do
      hide(%w[tracking users])
      group.add(admin)
      group.add(moderator)
      expect(hidden_pages(admin)).to be_nil
      expect(hidden_pages(moderator)).to be_nil
    end

    it "stops when the member leaves or the feature is disabled" do
      hide(%w[tracking users])
      SiteSetting.mute_enhancements_group_hide_preferences = false
      expect(hidden_pages(member)).to be_nil

      SiteSetting.mute_enhancements_group_hide_preferences = true
      group.remove(member)
      expect(hidden_pages(member)).to be_nil
    end
  end
end
