# frozen_string_literal: true

RSpec.describe DiscourseMuteEnhancements::GroupMutedTopicsController do
  fab!(:admin)
  fab!(:moderator)
  fab!(:group)
  fab!(:member, :user)
  fab!(:other_member, :user)
  fab!(:outsider, :user)
  fab!(:topic)
  fab!(:other_topic, :topic)

  let(:path) { "/mute-enhancements/groups/#{group.id}/muted-topics.json" }
  let(:muted) { TopicUser.notification_levels[:muted] }
  let(:watching) { TopicUser.notification_levels[:watching] }

  before do
    SiteSetting.mute_enhancements_enabled = true
    group.add(member)
    group.add(other_member)
  end

  def level(user, target = topic) = TopicUser.find_by(user:, topic: target)&.notification_level

  def saved_ids = DiscourseMuteEnhancements::GroupMutedTopics.topic_ids(group)

  it "is for admins only" do
    sign_in(moderator)
    put path, params: { topic_ids: topic.id.to_s }
    expect(response.status).to eq(403)

    owner = Fabricate(:user)
    group.add_owner(owner)
    sign_in(owner)
    put path, params: { topic_ids: topic.id.to_s }
    expect(response.status).to eq(403)

    expect(saved_ids).to be_empty
    expect(level(member)).to be_nil
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "mutes the topics for every member, whatever their level was" do
      TopicUser.change(member, topic, notification_level: watching)

      messages =
        MessageBus.track_publish("/topic/#{topic.id}") do
          put path, params: { topic_ids: "#{topic.id}\n\n #{other_topic.id}\n#{topic.id}\n" }
        end

      expect(response.status).to eq(200)
      expect(response.parsed_body["muted_topic_ids"]).to eq([topic.id, other_topic.id])
      expect(response.parsed_body["applied_user_count"]).to eq(2)
      expect(saved_ids).to eq([topic.id, other_topic.id])

      [member, other_member].each do |user|
        expect(level(user)).to eq(muted)
        expect(level(user, other_topic)).to eq(muted)
      end
      expect(level(outsider)).to be_nil
      expect(TopicUser.find_by(user: member, topic:).notifications_reason_id).to eq(
        TopicUser.notification_reasons[:user_changed],
      )
      expect(messages.first.user_ids).to contain_exactly(member.id, other_member.id)
      expect(messages.first.data[:notification_level_change]).to eq(muted)

      log = UserHistory.find_by(custom_type: "mute_enhancements_group_muted_topics")
      expect(log.details).to include(group.name, "#{topic.id}, #{other_topic.id}")
    end

    it "only mutes the added topics again when the list changes" do
      put path, params: { topic_ids: topic.id.to_s }
      TopicUser.change(member, topic, notification_level: watching)

      put path, params: { topic_ids: "#{topic.id}\n#{other_topic.id}" }
      expect(response.parsed_body["applied_user_count"]).to eq(2)
      expect(level(member)).to eq(watching)
      expect(level(member, other_topic)).to eq(muted)

      put path, params: { topic_ids: "#{topic.id}\n#{other_topic.id}" }
      expect(response.parsed_body["applied_user_count"]).to eq(0)

      put path, params: { topic_ids: "" }
      expect(response.status).to eq(200)
      expect(response.parsed_body["muted_topic_ids"]).to eq([])
      expect(GroupCustomField.where(group:, name: "mute_enhancements_muted_topics")).to be_empty
      expect(level(member, other_topic)).to eq(muted)

      expect(UserHistory.where(custom_type: "mute_enhancements_group_muted_topics").count).to eq(3)
    end

    it "rejects ids that are not topics, and saves nothing" do
      pm = Fabricate(:private_message_topic)
      deleted = Fabricate(:topic, deleted_at: Time.zone.now)

      put path,
          params: {
            topic_ids: "#{topic.id}\nabc\n#{pm.id}\n#{deleted.id}\n#{Topic.maximum(:id) + 100}",
          }
      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include("abc", pm.id.to_s, deleted.id.to_s)
      expect(saved_ids).to be_empty
      expect(level(member)).to be_nil

      put path
      expect(response.status).to eq(400)
    end

    it "rejects automatic groups" do
      put "/mute-enhancements/groups/#{Group::AUTO_GROUPS[:trust_level_1]}/muted-topics.json",
          params: {
            topic_ids: topic.id.to_s,
          }
      expect(response.status).to eq(400)
    end

    it "is not found when the setting is off" do
      SiteSetting.mute_enhancements_group_muted_topics = false
      put path, params: { topic_ids: topic.id.to_s }
      expect(response.status).to eq(404)
    end
  end

  describe "group members" do
    before { DiscourseMuteEnhancements::GroupMutedTopics.update(group, topic.id.to_s) }

    it "mutes the topics for users who join, and leaves them when they leave" do
      TopicUser.change(outsider, topic, notification_level: watching)
      group.add(outsider)
      expect(level(outsider)).to eq(muted)

      group.remove(outsider)
      expect(level(outsider)).to eq(muted)
    end

    it "keeps them muted when the member watches the topic's category" do
      CategoryUser.set_notification_level_for_category(
        member,
        CategoryUser.notification_levels[:watching],
        topic.category_id,
      )
      expect(level(member)).to eq(muted)
    end

    it "does nothing for users who join when the setting is off" do
      SiteSetting.mute_enhancements_group_muted_topics = false
      group.add(outsider)
      expect(level(outsider)).to be_nil
    end
  end

  describe "group show" do
    before { DiscourseMuteEnhancements::GroupMutedTopics.update(group, topic.id.to_s) }

    it "includes the topics for admins only" do
      sign_in(admin)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]["mute_enhancements_muted_topic_ids"]).to eq([topic.id])

      sign_in(moderator)
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_muted_topic_ids")
    end
  end
end
