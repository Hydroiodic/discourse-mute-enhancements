# frozen_string_literal: true

RSpec.describe DiscourseMuteEnhancements::GroupMutes do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:member, :user)
  fab!(:other_member, :user)
  fab!(:moderator)
  fab!(:group) { Fabricate(:group, visibility_level: Group.visibility_levels[:public]) }

  before do
    SiteSetting.mute_enhancements_enabled = true
    Group.refresh_automatic_groups!
    [user, member, other_member, moderator].each { |u| group.add(u) }
  end

  def muted_ids = MutedUser.where(user:).pluck(:muted_user_id)
  def ignored_ids = IgnoredUser.where(user:).pluck(:ignored_user_id)
  def levels = DiscourseMuteEnhancements::GroupMute.where(user:).pluck(:group_id, :level).to_h

  it "mutes every member of a muted group except the user and staff" do
    described_class.update(user, mute: [group.id])

    expect(levels).to eq(group.id => 1)
    expect(muted_ids).to contain_exactly(member.id, other_member.id)
    expect(ignored_ids).to be_empty
  end

  it "ignores every member of an ignored group, for good" do
    described_class.update(user, ignore: [group.id])

    expect(ignored_ids).to contain_exactly(member.id, other_member.id)
    expect(muted_ids).to be_empty
    row = IgnoredUser.find_by(user:, ignored_user: member)
    expect(row.expiring_at).to be > 100.years.from_now
  end

  it "does not report group ignores to moderators" do
    SiteSetting.ignored_users_count_message_threshold = 1
    described_class.update(user, ignore: [group.id])

    expect { Jobs::IgnoredUsersSummary.new.execute({}) }.not_to change {
      Topic.where(archetype: Archetype.private_message).count
    }
  end

  it "follows members who join and leave" do
    described_class.update(user, mute: [group.id])
    newcomer = Fabricate(:user)

    group.add(newcomer)
    expect(muted_ids).to contain_exactly(member.id, other_member.id, newcomer.id)

    group.remove(member)
    expect(muted_ids).to contain_exactly(other_member.id, newcomer.id)
  end

  it "keeps a member muted while another muted group still has them" do
    other_group = Fabricate(:group, visibility_level: Group.visibility_levels[:public])
    other_group.add(member)
    described_class.update(user, mute: [group.id, other_group.id])

    group.remove(member)
    expect(muted_ids).to include(member.id)

    described_class.update(user, mute: [group.id])
    expect(muted_ids).not_to include(member.id)
  end

  it "unmutes everyone when the group is unmuted" do
    described_class.update(user, mute: [group.id])
    described_class.update(user, mute: [])

    expect(levels).to be_empty
    expect(muted_ids).to be_empty
    expect(DiscourseMuteEnhancements::DerivedMute.count).to eq(0)
  end

  it "keeps users the user muted or ignored by hand" do
    MutedUser.create!(user:, muted_user: member)
    IgnoredUser.create!(user:, ignored_user: other_member, expiring_at: 1.week.from_now)

    described_class.update(user, mute: [group.id])
    described_class.update(user, mute: [])

    expect(muted_ids).to contain_exactly(member.id)
    expect(ignored_ids).to contain_exactly(other_member.id)
    expect(IgnoredUser.find_by(user:, ignored_user: other_member).expiring_at).to be <
      1.month.from_now
  end

  it "does not mute again a member the user unmuted by hand" do
    described_class.update(user, mute: [group.id])
    MutedUser.where(user:, muted_user: member).delete_all

    described_class.reconcile_all
    group.add(Fabricate(:user))
    expect(muted_ids).not_to include(member.id)

    described_class.update(user, mute: [])
    described_class.update(user, mute: [group.id])
    expect(muted_ids).to include(member.id)
  end

  it "does not mute someone the user ignores, until they no longer do" do
    IgnoredUser.create!(user:, ignored_user: member, expiring_at: 1.week.from_now)
    described_class.update(user, mute: [group.id])
    expect(muted_ids).to contain_exactly(other_member.id)

    IgnoredUser.where(user:, ignored_user: member).delete_all
    described_class.reconcile_all
    expect(muted_ids).to contain_exactly(member.id, other_member.id)
  end

  it "ignores a group that is in both lists" do
    described_class.update(user, mute: [group.id], ignore: [group.id])

    expect(levels).to eq(group.id => 2)
    expect(ignored_ids).to contain_exactly(member.id, other_member.id)
    expect(muted_ids).to be_empty
  end

  it "switches a group from muted to ignored" do
    described_class.update(user, mute: [group.id])
    described_class.update(user, mute: [], ignore: [group.id])

    expect(muted_ids).to be_empty
    expect(ignored_ids).to contain_exactly(member.id, other_member.id)
  end

  it "only lets users mute groups they can see the members of" do
    hidden = Fabricate(:group, visibility_level: Group.visibility_levels[:owners])
    hidden.add(member)
    members_hidden =
      Fabricate(
        :group,
        visibility_level: Group.visibility_levels[:public],
        members_visibility_level: Group.visibility_levels[:owners],
      )

    described_class.update(user, mute: [hidden.id, members_hidden.id])

    expect(levels).to be_empty
  end

  it "does not let users mute automatic groups" do
    described_class.update(user, mute: [Group::AUTO_GROUPS[:trust_level_0]])
    expect(levels).to be_empty
  end

  it "lets users remove a group they can no longer see" do
    described_class.update(user, mute: [group.id])
    group.update!(visibility_level: Group.visibility_levels[:owners])

    expect(described_class.choosable_groups(user)).to include(group)
    described_class.update(user, mute: [])
    expect(levels).to be_empty
  end

  it "leaves levels the user may not use alone" do
    user.update!(trust_level: TrustLevel[0])
    Group.refresh_automatic_groups!

    described_class.update(user, mute: [group.id], ignore: [group.id])
    expect(levels).to be_empty
  end

  it "unmutes members who became staff" do
    described_class.update(user, mute: [group.id])
    member.update!(moderator: true)

    Jobs::MuteEnhancementsReconcileGroupMutes.new.execute({})
    expect(muted_ids).to contain_exactly(other_member.id)
  end

  it "cleans up when the group is deleted" do
    described_class.update(user, mute: [group.id])
    group.destroy!

    expect(levels).to be_empty
    expect(muted_ids).to be_empty
  end

  it "stops following members when group mutes are off" do
    described_class.update(user, mute: [group.id])
    SiteSetting.mute_enhancements_group_mutes = false

    group.add(newcomer = Fabricate(:user))
    expect(muted_ids).not_to include(newcomer.id)
  end
end
