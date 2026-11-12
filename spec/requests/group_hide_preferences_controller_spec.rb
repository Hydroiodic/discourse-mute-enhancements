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

  def turn_on
    DiscourseMuteEnhancements::HiddenPreferences.update(group, true)
  end

  it "is for admins only" do
    sign_in(moderator)
    put path, params: { enabled: true }
    expect(response.status).to eq(403)

    owner = Fabricate(:user)
    group.add_owner(owner)
    sign_in(owner)
    put path, params: { enabled: true }
    expect(response.status).to eq(403)

    expect(DiscourseMuteEnhancements::HiddenPreferences.group_enabled?(group)).to eq(false)
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "turns it on and off, and logs each change" do
      put path, params: { enabled: true }
      expect(response.status).to eq(200)
      expect(response.parsed_body["hide_preferences"]).to eq(true)
      expect(DiscourseMuteEnhancements::HiddenPreferences.group_enabled?(group)).to eq(true)

      put path, params: { enabled: true }
      expect(response.status).to eq(200)

      put path, params: { enabled: false }
      expect(response.parsed_body["hide_preferences"]).to eq(false)
      expect(DiscourseMuteEnhancements::HiddenPreferences.group_enabled?(group)).to eq(false)

      logs = UserHistory.where(custom_type: "mute_enhancements_group_hide_preferences").order(:id)
      expect(logs.count).to eq(2)
      expect(logs.map(&:details)).to all(include(group.name))
    end

    it "rejects automatic groups" do
      put "/mute-enhancements/groups/#{Group::AUTO_GROUPS[:trust_level_1]}/hide-preferences.json",
          params: {
            enabled: true,
          }
      expect(response.status).to eq(400)
    end

    it "is not found when the feature is disabled" do
      SiteSetting.mute_enhancements_group_hide_preferences = false
      put path, params: { enabled: true }
      expect(response.status).to eq(404)
    end

    it "shows the setting on the group to admins only" do
      turn_on
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]["mute_enhancements_hide_preferences"]).to eq(true)

      sign_in(moderator)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_hide_preferences")
    end
  end

  describe "the current user" do
    it "lists the hidden pages for members only" do
      expect(hidden_pages(member)).to be_nil

      turn_on
      expect(hidden_pages(member)).to eq(%w[notifications users])
      expect(hidden_pages(outsider)).to be_nil
    end

    it "leaves admins and moderators alone" do
      turn_on
      group.add(admin)
      group.add(moderator)
      expect(hidden_pages(admin)).to be_nil
      expect(hidden_pages(moderator)).to be_nil
    end

    it "stops when the member leaves or the feature is disabled" do
      turn_on
      SiteSetting.mute_enhancements_group_hide_preferences = false
      expect(hidden_pages(member)).to be_nil

      SiteSetting.mute_enhancements_group_hide_preferences = true
      group.remove(member)
      expect(hidden_pages(member)).to be_nil
    end
  end
end
