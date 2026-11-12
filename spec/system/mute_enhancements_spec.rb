# frozen_string_literal: true

RSpec.describe "Mute enhancements" do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:admin)
  fab!(:member) { Fabricate(:user, username: "member") }
  fab!(:spammer) { Fabricate(:user, username: "spammer") }
  fab!(:group) do
    Fabricate(:group, name: "loud_group", visibility_level: Group.visibility_levels[:public])
  end

  before do
    enable_current_plugin
    Group.refresh_automatic_groups!
    group.add(member)
  end

  describe "muting and ignoring groups" do
    let(:muted_groups) do
      PageObjects::Components::SelectKit.new(".mute-enhancements-muted-groups .select-kit")
    end
    let(:ignored_groups) do
      PageObjects::Components::SelectKit.new(".mute-enhancements-ignored-groups .select-kit")
    end

    def save
      find(".save-changes").click
      expect(page).to have_css(".saved")
    end

    it "mutes a group from the preferences page, then ignores it instead" do
      sign_in(user)
      visit("/u/#{user.username}/preferences/users")

      muted_groups.expand
      muted_groups.select_row_by_value(group.id)
      muted_groups.collapse
      expect(muted_groups).to have_selected_name(group.name)

      ignored_groups.expand
      expect(ignored_groups).to have_no_option_value(group.id)
      ignored_groups.collapse

      save
      expect(MutedUser.where(user:).pluck(:muted_user_id)).to contain_exactly(member.id)
      expect(muted_groups).to have_selected_name(group.name)

      muted_groups.expand
      muted_groups.unselect_by_name(group.name)
      muted_groups.collapse
      expect(muted_groups).to have_selected_value("")

      ignored_groups.expand
      ignored_groups.select_row_by_value(group.id)
      ignored_groups.collapse
      expect(ignored_groups).to have_selected_name(group.name)

      save
      expect(MutedUser.where(user:)).to be_empty
      expect(IgnoredUser.where(user:).pluck(:ignored_user_id)).to contain_exactly(member.id)

      page.refresh
      expect(ignored_groups).to have_selected_name(group.name)
      expect(muted_groups).to have_selected_value("")
      expect(page).to have_no_css(".user-ignore .ignored-user-list-item")
    end
  end

  describe "default muted and ignored users of a group" do
    let(:default_muted) do
      PageObjects::Components::SelectKit.new(".select-kit.mute-enhancements-default-muted-users")
    end
    let(:default_notifications_modal) { PageObjects::Modals::GroupDefaultNotifications.new }

    it "saves the defaults and applies them to current members when asked" do
      sign_in(admin)
      visit("/g/#{group.name}/manage/membership")

      default_muted.expand
      default_muted.search(spammer.username)
      default_muted.select_row_by_value(spammer.username)
      default_muted.collapse

      find(".mute-enhancements-save-default-users").click
      default_notifications_modal.click_yes

      expect(page).to have_css(".mute-enhancements-save-default-users[disabled]")
      expect(MutedUser.where(user: member).pluck(:muted_user_id)).to contain_exactly(spammer.id)
      expect(
        DiscourseMuteEnhancements::GroupDefaultUser.where(group:).pluck(:target_user_id),
      ).to contain_exactly(spammer.id)

      page.refresh
      expect(default_muted).to have_selected_name(spammer.username)
    end

    it "is not shown to moderators who manage groups" do
      SiteSetting.moderators_manage_groups = true
      sign_in(Fabricate(:moderator))
      visit("/g/#{group.name}/manage/membership")

      expect(page).to have_css(".group-form-automatic-membership-automatic")
      expect(page).to have_no_css(".mute-enhancements-default-users")
    end
  end
end
