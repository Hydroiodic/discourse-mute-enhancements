# frozen_string_literal: true

RSpec.describe DiscourseMuteEnhancements::GroupDefaultUsersController do
  fab!(:admin)
  fab!(:moderator)
  fab!(:group)
  fab!(:member, :user)
  fab!(:spammer, :user)
  fab!(:troll, :user)

  let(:path) { "/mute-enhancements/groups/#{group.id}/default-users.json" }

  before do
    SiteSetting.mute_enhancements_enabled = true
    group.add(member)
  end

  def muted_ids(user) = MutedUser.where(user:).pluck(:muted_user_id)
  def ignored_ids(user) = IgnoredUser.where(user:).pluck(:ignored_user_id)
  def default_users = DiscourseMuteEnhancements::GroupDefaultUsers.levels(group)
  def default_groups = DiscourseMuteEnhancements::GroupDefaultGroups.levels(group)

  def save(**params)
    put path,
        params: {
          muted_usernames: spammer.username,
          ignored_usernames: troll.username,
          **params,
        }
  end

  it "is for admins only" do
    sign_in(moderator)
    save
    expect(response.status).to eq(403)

    owner = Fabricate(:user)
    group.add_owner(owner)
    sign_in(owner)
    save
    expect(response.status).to eq(403)

    expect(default_users).to be_empty
  end

  context "as an admin" do
    before { sign_in(admin) }

    it "gives the defaults to members who join, not to current members" do
      save

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "muted_usernames" => [spammer.username],
        "ignored_usernames" => [troll.username],
        "applied_user_count" => 0,
      )
      expect(muted_ids(member)).to be_empty
      expect(ignored_ids(member)).to be_empty

      newcomer = Fabricate(:user)
      group.add(newcomer)
      expect(muted_ids(newcomer)).to contain_exactly(spammer.id)
      expect(ignored_ids(newcomer)).to contain_exactly(troll.id)
      ignore = IgnoredUser.find_by(user: newcomer, ignored_user: troll)
      expect(ignore.expiring_at).to be > 100.years.from_now
      expect(ignore.summarized_at).to be_present
    end

    it "gives current members the defaults that were added when asked" do
      save(ignored_usernames: "")
      save(update_existing_users: true)

      expect(response.parsed_body["applied_user_count"]).to eq(1)
      expect(muted_ids(member)).to be_empty
      expect(ignored_ids(member)).to contain_exactly(troll.id)
    end

    it "does not change what members set themselves" do
      IgnoredUser.create!(user: member, ignored_user: spammer, expiring_at: 1.week.from_now)
      MutedUser.create!(user: member, muted_user: troll)

      save(update_existing_users: true)

      expect(response.parsed_body["applied_user_count"]).to eq(0)
      expect(muted_ids(member)).to contain_exactly(troll.id)
      expect(ignored_ids(member)).to contain_exactly(spammer.id)
    end

    it "does not make a default user mute themselves" do
      save
      group.add(spammer)
      expect(muted_ids(spammer)).to be_empty
      expect(ignored_ids(spammer)).to contain_exactly(troll.id)
    end

    it "leaves members' rows in place when defaults are removed or members leave" do
      save(update_existing_users: true)
      put path, params: { muted_usernames: "", ignored_usernames: "" }
      group.remove(member)

      expect(default_users).to be_empty
      expect(GroupCustomField.where(group_id: group.id)).to be_empty
      expect(muted_ids(member)).to contain_exactly(spammer.id)
      expect(ignored_ids(member)).to contain_exactly(troll.id)
    end

    it "ignores a user that is in both lists" do
      save(muted_usernames: troll.username)
      expect(response.parsed_body).to include(
        "muted_usernames" => [],
        "ignored_usernames" => [troll.username],
      )
    end

    it "rejects staff" do
      save(muted_usernames: moderator.username)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include(moderator.username)
      expect(default_users).to be_empty
    end

    it "rejects automatic groups" do
      put "/mute-enhancements/groups/#{Group::AUTO_GROUPS[:trust_level_0]}/default-users.json",
          params: {
            muted_usernames: spammer.username,
          }
      expect(response.status).to eq(400)
    end

    it "logs a staff action" do
      save
      log = UserHistory.find_by(custom_type: "mute_enhancements_group_default_users")
      expect(log.details).to include(group.name, spammer.username, troll.username)
    end

    it "is not found when the setting is off" do
      SiteSetting.mute_enhancements_group_default_users = false
      save
      expect(response.status).to eq(404)
    end

    it "shows the defaults on the group" do
      save
      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]["mute_enhancements_default_users"]).to eq(
        "muted_usernames" => [spammer.username],
        "ignored_usernames" => [troll.username],
      )
    end

    it "removes the defaults with the group" do
      save
      group.destroy!
      expect(GroupCustomField.where(group_id: group.id)).to be_empty
    end
  end

  it "does not show the defaults to non-admins" do
    sign_in(moderator)
    get "/groups/#{group.name}.json"
    expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_default_users")
    expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_default_groups")
  end

  describe "default groups" do
    fab!(:loud_group) { Fabricate(:group, name: "loud") }
    fab!(:loud_member) { Fabricate(:user).tap { |u| loud_group.add(u) } }
    fab!(:noisy_group) { Fabricate(:group, name: "noisy") }
    fab!(:noisy_member) { Fabricate(:user).tap { |u| noisy_group.add(u) } }

    def group_mutes(user) = DiscourseMuteEnhancements::GroupMutes.levels(user)

    def save_groups(muted: noisy_group.id.to_s, ignored: loud_group.id.to_s, **params)
      put path,
          params: {
            muted_usernames: "",
            ignored_usernames: "",
            muted_group_ids: muted,
            ignored_group_ids: ignored,
            **params,
          }
    end

    before { sign_in(admin) }

    it "gives members who join a group mute of their own, which follows that group" do
      save_groups

      expect(response.status).to eq(200)
      expect(response.parsed_body).to include(
        "muted_group_ids" => [noisy_group.id],
        "ignored_group_ids" => [loud_group.id],
        "applied_user_count" => 0,
      )
      expect(group_mutes(member)).to be_empty

      newcomer = Fabricate(:user)
      group.add(newcomer)
      expect(group_mutes(newcomer)).to eq(
        noisy_group.id => DiscourseMuteEnhancements::LEVELS[:mute],
        loud_group.id => DiscourseMuteEnhancements::LEVELS[:ignore],
      )
      expect(muted_ids(newcomer)).to contain_exactly(noisy_member.id)
      expect(ignored_ids(newcomer)).to contain_exactly(loud_member.id)

      later = Fabricate(:user)
      loud_group.add(later)
      expect(ignored_ids(newcomer)).to contain_exactly(loud_member.id, later.id)
    end

    it "gives current members the groups that were added when asked, counting each member once" do
      save_groups(ignored: "", muted_usernames: spammer.username, update_existing_users: true)
      expect(response.parsed_body["applied_user_count"]).to eq(1)

      save_groups(update_existing_users: true)
      expect(response.parsed_body["applied_user_count"]).to eq(1)
      expect(group_mutes(member).keys).to contain_exactly(noisy_group.id, loud_group.id)
      expect(muted_ids(member)).to contain_exactly(spammer.id, noisy_member.id)
      expect(ignored_ids(member)).to contain_exactly(loud_member.id)
    end

    it "does not change a group the member already muted or ignored" do
      DiscourseMuteEnhancements::UserStore.merge(
        "group_mutes",
        { member.id => { loud_group.id => DiscourseMuteEnhancements::LEVELS[:mute] } },
      )

      save_groups(update_existing_users: true)

      expect(group_mutes(member)).to eq(
        noisy_group.id => DiscourseMuteEnhancements::LEVELS[:mute],
        loud_group.id => DiscourseMuteEnhancements::LEVELS[:mute],
      )
    end

    it "leaves the group mutes in place when defaults are removed or members leave" do
      save_groups(update_existing_users: true)
      save_groups(muted: "", ignored: "")
      group.remove(member)

      expect(default_groups).to be_empty
      expect(group_mutes(member).keys).to contain_exactly(noisy_group.id, loud_group.id)
    end

    it "ignores a group that is in both lists" do
      save_groups(muted: "#{noisy_group.id},#{loud_group.id}")
      expect(response.parsed_body).to include(
        "muted_group_ids" => [noisy_group.id],
        "ignored_group_ids" => [loud_group.id],
      )
    end

    it "rejects automatic groups and the group itself, and saves nothing" do
      save_groups(
        ignored: Group::AUTO_GROUPS[:trust_level_1].to_s,
        muted_usernames: spammer.username,
      )
      expect(response.status).to eq(422)

      save_groups(ignored: group.id.to_s, muted_usernames: spammer.username)
      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include(group.name)

      expect(default_groups).to be_empty
      expect(default_users).to be_empty
    end

    it "allows hidden groups, which members can remove but not add back" do
      hidden =
        Fabricate(
          :group,
          name: "hidden",
          visibility_level: Group.visibility_levels[:owners],
          members_visibility_level: Group.visibility_levels[:owners],
        )
      hidden_member = Fabricate(:user)
      hidden.add(hidden_member)
      member.update!(trust_level: TrustLevel[2])
      Group.refresh_automatic_groups!

      save_groups(muted: "", ignored: hidden.id.to_s, update_existing_users: true)
      expect(response.status).to eq(200)
      expect(response.parsed_body["ignored_group_ids"]).to eq([hidden.id])
      expect(group_mutes(member).keys).to contain_exactly(hidden.id)
      expect(ignored_ids(member)).to contain_exactly(hidden_member.id)

      sign_in(member)
      get "/u/#{member.username}.json"
      shown = response.parsed_body["user"]
      expect(shown["mute_enhancements_ignored_group_ids"]).to eq(hidden.id.to_s)
      expect(shown["mute_enhancements_available_groups"].map { |g| g["name"] }).to include("hidden")

      DiscourseMuteEnhancements::GroupMutes.update(member, ignore: [])
      expect(group_mutes(member)).to be_empty
      expect(ignored_ids(member)).to be_empty

      DiscourseMuteEnhancements::GroupMutes.update(member, ignore: [hidden.id])
      expect(group_mutes(member)).to be_empty
    end

    it "leaves the default groups alone when they are not sent" do
      save_groups
      save
      expect(default_groups.keys).to contain_exactly(noisy_group.id, loud_group.id)
    end

    it "logs the groups" do
      save_groups
      log = UserHistory.where(custom_type: "mute_enhancements_group_default_users").last
      expect(log.details).to include("loud", "noisy")
    end

    it "shows the defaults and the groups to choose from on the group" do
      hidden = Fabricate(:group, name: "hidden", visibility_level: Group.visibility_levels[:owners])
      save_groups

      get "/groups/#{group.name}.json"
      defaults = response.parsed_body["group"]["mute_enhancements_default_groups"]
      expect(defaults).to include(
        "muted_group_ids" => [noisy_group.id],
        "ignored_group_ids" => [loud_group.id],
      )
      names = defaults["available_groups"].map { |g| g["name"] }
      expect(names).to include("loud", "noisy", hidden.name)
      expect(names).not_to include(group.name, "trust_level_1")
    end

    it "removes the defaults with either group" do
      save_groups
      # Another field of the group, which is not JSON.
      DiscourseMuteEnhancements::GroupMutedTopics.update(group, Fabricate(:topic).id.to_s)

      loud_group.destroy!
      expect(default_groups).to eq(noisy_group.id => DiscourseMuteEnhancements::LEVELS[:mute])

      group.destroy!
      expect(GroupCustomField.where(group_id: group.id)).to be_empty
    end

    it "is off without group mutes" do
      SiteSetting.mute_enhancements_group_mutes = false
      save_groups(muted_usernames: spammer.username)

      expect(response.status).to eq(200)
      expect(response.parsed_body).not_to have_key("muted_group_ids")
      expect(default_groups).to be_empty
      expect(default_users.keys).to eq([spammer.id])

      get "/groups/#{group.name}.json"
      expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_default_groups")
    end
  end
end
