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

    expect(DiscourseMuteEnhancements::GroupDefaultUser.count).to eq(0)
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

      expect(DiscourseMuteEnhancements::GroupDefaultUser.count).to eq(0)
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
      expect(DiscourseMuteEnhancements::GroupDefaultUser.count).to eq(0)
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
      expect(DiscourseMuteEnhancements::GroupDefaultUser.count).to eq(0)
    end
  end

  it "does not show the defaults to non-admins" do
    sign_in(moderator)
    get "/groups/#{group.name}.json"
    expect(response.parsed_body["group"]).not_to have_key("mute_enhancements_default_users")
  end
end
