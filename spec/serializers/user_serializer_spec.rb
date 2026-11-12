# frozen_string_literal: true

RSpec.describe UserSerializer do
  fab!(:user)
  fab!(:admin)
  fab!(:public_group) { Fabricate(:group, visibility_level: Group.visibility_levels[:public]) }
  fab!(:owners_group) do
    Fabricate(
      :group,
      visibility_level: Group.visibility_levels[:owners],
      members_visibility_level: Group.visibility_levels[:owners],
    )
  end
  fab!(:staff_group) { Fabricate(:group, visibility_level: Group.visibility_levels[:staff]) }

  before do
    SiteSetting.mute_enhancements_enabled = true
    [public_group, owners_group, staff_group].each { |group| group.add(user) }
  end

  def group_user_ids(viewer)
    described_class.new(user, scope: Guardian.new(viewer), root: false).as_json[
      :group_users
    ].map { |group_user| group_user[:group_id] }
  end

  describe "#group_users" do
    it "leaves out groups the user cannot see" do
      expect(group_user_ids(user)).to contain_exactly(public_group.id)
    end

    it "keeps groups the user owns" do
      owners_group.add_owner(user)
      expect(group_user_ids(user)).to contain_exactly(public_group.id, owners_group.id)
    end

    it "lists every group for admins" do
      expect(group_user_ids(admin)).to contain_exactly(
        public_group.id,
        owners_group.id,
        staff_group.id,
      )
    end

    it "lists every group when the setting is off" do
      SiteSetting.mute_enhancements_hide_invisible_group_users = false
      expect(group_user_ids(user)).to contain_exactly(
        public_group.id,
        owners_group.id,
        staff_group.id,
      )
    end

    it "lists every group when the plugin is disabled" do
      SiteSetting.mute_enhancements_enabled = false
      expect(group_user_ids(user).size).to eq(3)
    end
  end

  describe "muted and ignored users lists" do
    fab!(:member) { Fabricate(:user, trust_level: TrustLevel[1]) }
    fab!(:muted_by_hand, :user)
    fab!(:ignored_by_hand, :user)

    before do
      user.update!(trust_level: TrustLevel[2])
      Group.refresh_automatic_groups!
      public_group.add(member)
      MutedUser.create!(user:, muted_user: muted_by_hand)
      IgnoredUser.create!(user:, ignored_user: ignored_by_hand, expiring_at: 1.month.from_now)
    end

    def lists
      json = described_class.new(user, scope: Guardian.new(user), root: false).as_json
      [json[:muted_usernames], json[:ignored_usernames]]
    end

    it "leaves out members of muted groups" do
      DiscourseMuteEnhancements::GroupMutes.update(user, mute: [public_group.id])
      expect(MutedUser.where(user:).pluck(:muted_user_id)).to include(member.id)

      expect(lists).to eq([[muted_by_hand.username], [ignored_by_hand.username]])
    end

    it "leaves out members of ignored groups" do
      DiscourseMuteEnhancements::GroupMutes.update(user, ignore: [public_group.id])
      expect(IgnoredUser.where(user:).pluck(:ignored_user_id)).to include(member.id)

      expect(lists).to eq([[muted_by_hand.username], [ignored_by_hand.username]])
    end

    it "lists everyone when group mutes are off" do
      DiscourseMuteEnhancements::GroupMutes.update(user, mute: [public_group.id])
      SiteSetting.mute_enhancements_group_mutes = false

      expect(lists.first).to contain_exactly(muted_by_hand.username, member.username)
    end
  end
end
