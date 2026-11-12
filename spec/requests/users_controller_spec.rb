# frozen_string_literal: true

RSpec.describe UsersController do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:member, :user)
  fab!(:other_member, :user)
  fab!(:muted_by_hand, :user)
  fab!(:group) { Fabricate(:group, visibility_level: Group.visibility_levels[:public]) }
  fab!(:other_group) { Fabricate(:group, visibility_level: Group.visibility_levels[:public]) }

  before do
    SiteSetting.mute_enhancements_enabled = true
    Group.refresh_automatic_groups!
    group.add(member)
    group.add(other_member)
    other_group.add(member)
    sign_in(user)
  end

  def muted_ids = MutedUser.where(user:).pluck(:muted_user_id)
  def ignored_ids = IgnoredUser.where(user:).pluck(:ignored_user_id)

  def save(**params)
    put "/u/#{user.username}.json", params: params
    expect(response.status).to eq(200)
  end

  it "saves muted and ignored groups from the preferences page" do
    save(
      mute_enhancements_muted_group_ids: group.id.to_s,
      mute_enhancements_ignored_group_ids: other_group.id.to_s,
    )

    expect(muted_ids).to contain_exactly(other_member.id)
    expect(ignored_ids).to contain_exactly(member.id)

    get "/u/#{user.username}.json"
    json = response.parsed_body["user"]
    expect(json["mute_enhancements_muted_group_ids"]).to eq(group.id.to_s)
    expect(json["mute_enhancements_ignored_group_ids"]).to eq(other_group.id.to_s)
    expect(json["mute_enhancements_available_groups"].map { |g| g["id"] }).to include(
      group.id,
      other_group.id,
    )
    expect(json["muted_usernames"]).to eq([])
    expect(json["ignored_usernames"]).to eq([])
  end

  it "clears the groups with empty lists" do
    save(mute_enhancements_muted_group_ids: group.id.to_s)
    save(mute_enhancements_muted_group_ids: "")

    expect(muted_ids).to be_empty
  end

  it "keeps members of muted groups when the page saves the muted users list" do
    save(mute_enhancements_muted_group_ids: group.id.to_s)

    save(muted_usernames: muted_by_hand.username, mute_enhancements_muted_group_ids: group.id.to_s)
    expect(muted_ids).to contain_exactly(member.id, other_member.id, muted_by_hand.id)

    save(muted_usernames: "", mute_enhancements_muted_group_ids: group.id.to_s)
    expect(muted_ids).to contain_exactly(member.id, other_member.id)
  end

  it "keeps a member the user unmuted by hand unmuted when the page saves" do
    save(mute_enhancements_muted_group_ids: group.id.to_s)
    put "/u/#{member.username}/notification_level.json", params: { notification_level: "normal" }
    expect(response.status).to eq(200)
    expect(muted_ids).to contain_exactly(other_member.id)

    save(muted_usernames: "", mute_enhancements_muted_group_ids: group.id.to_s)
    expect(muted_ids).to contain_exactly(other_member.id)
  end

  it "keeps members the user also adds to the muted users list when the group is unmuted" do
    save(mute_enhancements_muted_group_ids: group.id.to_s)

    save(muted_usernames: member.username, mute_enhancements_muted_group_ids: "")
    expect(muted_ids).to contain_exactly(member.id)
  end

  it "does not add groups the user cannot see" do
    hidden = Fabricate(:group, visibility_level: Group.visibility_levels[:owners])
    save(mute_enhancements_muted_group_ids: hidden.id.to_s)

    expect(DiscourseMuteEnhancements::GroupMute.count).to eq(0)
  end

  it "lets admins edit the groups of other users" do
    sign_in(Fabricate(:admin))
    save(mute_enhancements_muted_group_ids: group.id.to_s)

    expect(muted_ids).to contain_exactly(member.id, other_member.id)
  end

  it "does not show the groups to other users" do
    sign_in(Fabricate(:user))
    get "/u/#{user.username}.json"

    expect(response.parsed_body["user"]).not_to have_key("mute_enhancements_muted_group_ids")
    expect(response.parsed_body["user"]).not_to have_key("mute_enhancements_available_groups")
  end

  it "ignores the lists when group mutes are off" do
    SiteSetting.mute_enhancements_group_mutes = false
    save(mute_enhancements_muted_group_ids: group.id.to_s)

    expect(muted_ids).to be_empty
    get "/u/#{user.username}.json"
    expect(response.parsed_body["user"]).not_to have_key("mute_enhancements_muted_group_ids")
  end
end
