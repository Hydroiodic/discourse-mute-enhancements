# frozen_string_literal: true

RSpec.describe DiscourseMuteEnhancements::GroupEnhancedIgnoreController do
  fab!(:admin)
  fab!(:moderator)
  fab!(:group)
  fab!(:member, :user)
  fab!(:other_member, :user)
  fab!(:outsider, :user)

  let(:path) { "/mute-enhancements/groups/#{group.id}/enhanced-ignore.json" }
  let(:all_options) { "hide_ignored_topics,ignored_user_cannot_reply_to_me" }

  before do
    skip("needs the enhanced-ignore plugin") if !SiteSetting.respond_to?(:enhanced_ignore_enabled)
    SiteSetting.mute_enhancements_enabled = true
    SiteSetting.enhanced_ignore_enabled = true
    group.add(member)
    group.add(other_member)
  end

  def preference(user, name = "hide_ignored_topics") = User.find(user.id).custom_fields[name]

  def set_preference(user, name, value)
    user.custom_fields[name] = value
    user.save_custom_fields
  end

  def group_options = DiscourseMuteEnhancements::GroupEnhancedIgnore.group_options(group)

  it "is for admins only" do
    sign_in(moderator)
    put path, params: { options: all_options }
    expect(response.status).to eq(403)

    owner = Fabricate(:user)
    group.add_owner(owner)
    sign_in(owner)
    put path, params: { options: all_options }
    expect(response.status).to eq(403)

    expect(group_options).to be_empty
    expect(preference(member)).to be_nil
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "turns the chosen options on for every member, whatever they were" do
      set_preference(member, "hide_ignored_topics", false)

      put path, params: { options: "hide_ignored_topics" }

      expect(response.status).to eq(200)
      expect(response.parsed_body["enhanced_ignore"]).to eq(%w[hide_ignored_topics])
      expect(response.parsed_body["applied_user_count"]).to eq(2)
      expect(group_options).to eq(%w[hide_ignored_topics])

      expect(preference(member)).to eq(true)
      expect(preference(other_member)).to eq(true)
      expect(preference(outsider)).to be_nil
      expect(preference(member, "ignored_user_cannot_reply_to_me")).to be_nil
      expect(UserCustomField.where(user_id: member.id, name: "hide_ignored_topics").count).to eq(1)

      log = UserHistory.find_by(custom_type: "mute_enhancements_group_enhanced_ignore")
      expect(log.details).to include(group.name, "hide_ignored_topics")
    end

    it "makes enhanced-ignore hide ignored users' topics and block their replies" do
      ignored = Fabricate(:user)
      IgnoredUser.create!(user: member, ignored_user: ignored, expiring_at: 1.year.from_now)
      ignored_topic = Fabricate(:topic, user: ignored)
      member_topic = Fabricate(:topic, user: member)
      latest = -> { TopicQuery.new(User.find(member.id)).list_latest.topics }
      can_reply = -> { Guardian.new(ignored).can_create_post_on_topic?(member_topic.reload) }

      expect(latest.call).to include(ignored_topic)
      expect(can_reply.call).to eq(true)

      put path, params: { options: all_options }
      expect(latest.call).not_to include(ignored_topic)
      expect(can_reply.call).to eq(false)
    end

    it "only turns the added options on again, and leaves members as they are when removed" do
      put path, params: { options: "hide_ignored_topics" }
      set_preference(member, "hide_ignored_topics", false)

      put path, params: { options: "ignored_user_cannot_reply_to_me,hide_ignored_topics" }
      expect(response.parsed_body["enhanced_ignore"]).to eq(all_options.split(","))
      expect(response.parsed_body["applied_user_count"]).to eq(2)
      expect(preference(member)).to eq(false)
      expect(preference(member, "ignored_user_cannot_reply_to_me")).to eq(true)

      put path, params: { options: all_options }
      expect(response.parsed_body["applied_user_count"]).to eq(0)

      put path, params: { options: "" }
      expect(response.status).to eq(200)
      expect(response.parsed_body["enhanced_ignore"]).to eq([])
      expect(GroupCustomField.where(group:, name: "mute_enhancements_enhanced_ignore")).to be_empty
      expect(preference(other_member)).to eq(true)
      expect(preference(other_member, "ignored_user_cannot_reply_to_me")).to eq(true)

      expect(UserHistory.where(custom_type: "mute_enhancements_group_enhanced_ignore").count).to eq(
        3,
      )
    end

    it "rejects unknown options and a missing value" do
      put path, params: { options: "hide_ignored_topics,something_else" }
      expect(response.status).to eq(400)
      expect(group_options).to be_empty
      expect(preference(member)).to be_nil

      put path
      expect(response.status).to eq(400)
    end

    it "rejects automatic groups" do
      put "/mute-enhancements/groups/#{Group::AUTO_GROUPS[:trust_level_1]}/enhanced-ignore.json",
          params: {
            options: all_options,
          }
      expect(response.status).to eq(400)
    end

    it "is not found when the setting or enhanced-ignore is off" do
      SiteSetting.mute_enhancements_group_enhanced_ignore = false
      put path, params: { options: all_options }
      expect(response.status).to eq(404)

      SiteSetting.mute_enhancements_group_enhanced_ignore = true
      SiteSetting.enhanced_ignore_enabled = false
      put path, params: { options: all_options }
      expect(response.status).to eq(404)
      expect(group_options).to be_empty
    end
  end

  describe "group members" do
    before { DiscourseMuteEnhancements::GroupEnhancedIgnore.update(group, all_options) }

    it "turns the options on for users who join, and leaves them when they leave" do
      set_preference(outsider, "hide_ignored_topics", false)
      group.add(outsider)
      expect(preference(outsider)).to eq(true)
      expect(preference(outsider, "ignored_user_cannot_reply_to_me")).to eq(true)

      group.remove(outsider)
      expect(preference(outsider)).to eq(true)
    end

    it "does nothing for users who join when enhanced-ignore is off" do
      SiteSetting.enhanced_ignore_enabled = false
      group.add(outsider)
      expect(preference(outsider)).to be_nil
    end
  end

  describe "group show" do
    it "includes the options for admins while enhanced-ignore is on" do
      DiscourseMuteEnhancements::GroupEnhancedIgnore.update(group, "hide_ignored_topics")

      sign_in(admin)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]["mute_enhancements_enhanced_ignore"]).to eq(
        %w[hide_ignored_topics],
      )

      SiteSetting.enhanced_ignore_enabled = false
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_enhanced_ignore")

      SiteSetting.enhanced_ignore_enabled = true
      sign_in(moderator)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_enhanced_ignore")
    end
  end
end
