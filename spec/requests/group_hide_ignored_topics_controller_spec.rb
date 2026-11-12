# frozen_string_literal: true

RSpec.describe DiscourseMuteEnhancements::GroupHideIgnoredTopicsController do
  fab!(:admin)
  fab!(:moderator)
  fab!(:group)
  fab!(:member, :user)
  fab!(:other_member, :user)
  fab!(:outsider, :user)

  let(:path) { "/mute-enhancements/groups/#{group.id}/hide-ignored-topics.json" }
  let(:field) { DiscourseMuteEnhancements::GroupHideIgnoredTopics::USER_FIELD }

  before do
    skip("needs the enhanced-ignore plugin") if !SiteSetting.respond_to?(:enhanced_ignore_enabled)
    SiteSetting.mute_enhancements_enabled = true
    SiteSetting.enhanced_ignore_enabled = true
    group.add(member)
    group.add(other_member)
  end

  def hides?(user) = User.find(user.id).custom_fields[field]

  def set_preference(user, value)
    user.custom_fields[field] = value
    user.save_custom_fields
  end

  def group_on? = DiscourseMuteEnhancements::GroupHideIgnoredTopics.on?(group)

  it "is for admins only" do
    sign_in(moderator)
    put path, params: { enabled: true }
    expect(response.status).to eq(403)

    owner = Fabricate(:user)
    group.add_owner(owner)
    sign_in(owner)
    put path, params: { enabled: true }
    expect(response.status).to eq(403)

    expect(group_on?).to eq(false)
    expect(hides?(member)).to be_nil
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "turns the preference on for every member, whatever it was" do
      set_preference(member, false)

      put path, params: { enabled: true }

      expect(response.status).to eq(200)
      expect(response.parsed_body["hide_ignored_topics"]).to eq(true)
      expect(response.parsed_body["applied_user_count"]).to eq(2)
      expect(group_on?).to eq(true)

      expect(hides?(member)).to eq(true)
      expect(hides?(other_member)).to eq(true)
      expect(hides?(outsider)).to be_nil
      expect(UserCustomField.where(user_id: member.id, name: field).count).to eq(1)

      log = UserHistory.find_by(custom_type: "mute_enhancements_group_hide_ignored_topics")
      expect(log.details).to include(group.name)
    end

    it "hides topics by users that members ignore from their topic lists" do
      ignored = Fabricate(:user)
      IgnoredUser.create!(user: member, ignored_user: ignored, expiring_at: 1.year.from_now)
      topic = Fabricate(:topic, user: ignored)
      latest = -> { TopicQuery.new(User.find(member.id)).list_latest.topics }

      expect(latest.call).to include(topic)
      put path, params: { enabled: true }
      expect(latest.call).not_to include(topic)
    end

    it "leaves members' preference as it is when turned off or saved again" do
      put path, params: { enabled: true }
      set_preference(member, false)

      put path, params: { enabled: true }
      expect(response.parsed_body["applied_user_count"]).to eq(0)
      expect(hides?(member)).to eq(false)

      put path, params: { enabled: false }
      expect(response.status).to eq(200)
      expect(response.parsed_body["hide_ignored_topics"]).to eq(false)
      expect(group_on?).to eq(false)
      expect(hides?(other_member)).to eq(true)

      expect(
        UserHistory.where(custom_type: "mute_enhancements_group_hide_ignored_topics").count,
      ).to eq(2)
    end

    it "rejects a missing or invalid value" do
      put path
      expect(response.status).to eq(400)

      put path, params: { enabled: "maybe" }
      expect(response.status).to eq(400)
      expect(group_on?).to eq(false)
    end

    it "rejects automatic groups" do
      put "/mute-enhancements/groups/#{Group::AUTO_GROUPS[:trust_level_1]}/hide-ignored-topics.json",
          params: {
            enabled: true,
          }
      expect(response.status).to eq(400)
    end

    it "is not found when the setting or enhanced-ignore is off" do
      SiteSetting.mute_enhancements_group_hide_ignored_topics = false
      put path, params: { enabled: true }
      expect(response.status).to eq(404)

      SiteSetting.mute_enhancements_group_hide_ignored_topics = true
      SiteSetting.enhanced_ignore_enabled = false
      put path, params: { enabled: true }
      expect(response.status).to eq(404)
      expect(group_on?).to eq(false)
    end
  end

  describe "group members" do
    before { DiscourseMuteEnhancements::GroupHideIgnoredTopics.update(group, true) }

    it "turns the preference on for users who join, and leaves it when they leave" do
      set_preference(outsider, false)
      group.add(outsider)
      expect(hides?(outsider)).to eq(true)

      group.remove(outsider)
      expect(hides?(outsider)).to eq(true)
    end

    it "does nothing for users who join when enhanced-ignore is off" do
      SiteSetting.enhanced_ignore_enabled = false
      group.add(outsider)
      expect(hides?(outsider)).to be_nil
    end
  end

  describe "group show" do
    it "includes the setting for admins while enhanced-ignore is on" do
      DiscourseMuteEnhancements::GroupHideIgnoredTopics.update(group, true)

      sign_in(admin)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]["mute_enhancements_hide_ignored_topics"]).to eq(true)

      SiteSetting.enhanced_ignore_enabled = false
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_hide_ignored_topics")

      SiteSetting.enhanced_ignore_enabled = true
      sign_in(moderator)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_hide_ignored_topics")
    end
  end
end
