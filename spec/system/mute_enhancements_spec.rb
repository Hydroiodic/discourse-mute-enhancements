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

    it "only shows the groups on the Users page, which saves them" do
      sign_in(user)
      visit("/u/#{user.username}/preferences/account")
      expect(page).to have_css(".user-nav__preferences-account")
      expect(page).to have_no_css(".mute-enhancements-muted-groups")

      visit("/u/#{user.username}/preferences/users")
      expect(page).to have_css(".mute-enhancements-muted-groups")
      expect(page).to have_css(".mute-enhancements-ignored-groups")
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

  describe "search suggestions" do
    let(:search_page) { PageObjects::Pages::Search.new }
    let(:composer) { PageObjects::Components::Composer.new }

    fab!(:ignored_user) { Fabricate(:user, username: "needleignored") }
    fab!(:other_user) { Fabricate(:user, username: "needleother") }
    fab!(:muted_category) { Fabricate(:category, name: "Needle muted", slug: "needle-muted") }
    fab!(:regular_category) { Fabricate(:category, name: "Needle regular", slug: "needle-regular") }
    fab!(:muted_tag) { Fabricate(:tag, name: "needle-muted-tag") }
    fab!(:regular_tag) { Fabricate(:tag, name: "needle-regular-tag") }

    before do
      SiteSetting.tagging_enabled = true
      Fabricate(:theme_site_setting_with_service, name: "enable_welcome_banner", value: false)
      SearchIndexer.enable
      [ignored_user, other_user].each { |u| SearchIndexer.index(u, force: true) }
      IgnoredUser.create!(user:, ignored_user:, expiring_at: 1.month.from_now)
      CategoryUser.set_notification_level_for_category(
        user,
        CategoryUser.notification_levels[:muted],
        muted_category.id,
      )
      TagUser.create!(
        user:,
        tag: muted_tag,
        notification_level: TagUser.notification_levels[:muted],
      )
      sign_in(user)
    end

    it "leaves out ignored users after @ in the search menu" do
      visit("/")
      search_page.click_search_icon
      search_page.type_in_search_menu("@needle")

      expect(page).to have_css(".search-menu-assistant-item.user", text: "needleother")
      expect(page).to have_no_css(".search-menu-assistant-item.user", text: "needleignored")
    end

    it "leaves out muted categories and tags after # in the search menu" do
      visit("/")
      search_page.click_search_icon
      search_page.type_in_search_menu("#needle")

      expect(page).to have_css(".search-menu-assistant-item.category", text: "Needle regular")
      expect(page).to have_css(".search-menu-assistant-item.tag", text: "needle-regular-tag")
      expect(page).to have_no_css(".search-menu-assistant-item.category", text: "Needle muted")
      expect(page).to have_no_css(".search-menu-assistant-item.tag", text: "needle-muted-tag")
    end

    it "leaves them out of the full page search for users and for categories and tags" do
      visit("/search?q=needle&search_type=users")
      expect(page).to have_css(".fps-user-item", text: "needleother")
      expect(page).to have_no_css(".fps-user-item", text: "needleignored")

      visit("/search?q=needle&search_type=categories_tags")
      expect(page).to have_css(".category-items", text: "Needle regular")
      expect(page).to have_css(".fps-tag-item", text: "needle-regular-tag")
      expect(page).to have_no_css(".category-items", text: "Needle muted")
      expect(page).to have_no_css(".fps-tag-item", text: "needle-muted-tag")
    end

    # Each page load searches once on its own; these search again on the same page. The second
    # terms only match what is left out, so nothing is found.
    it "leaves them out when searching again with the button of the full page search" do
      no_results = I18n.t("js.search.no_results")

      visit("/search?q=needle&search_type=users")
      expect(page).to have_css(".fps-user-item", text: "needleother")
      search_page.clear_search_input
      search_page.type_in_search("needleign")
      search_page.click_search_button
      expect(page).to have_css(".search-results h3", text: no_results)
      expect(page).to have_no_css(".fps-user-item", text: "needleignored")

      visit("/search?q=needle&search_type=categories_tags")
      expect(page).to have_css(".fps-tag-item", text: "needle-regular-tag")
      search_page.clear_search_input
      search_page.type_in_search("needle-m")
      search_page.click_search_button
      expect(page).to have_css(".search-results h3", text: no_results)
      expect(page).to have_no_css(".category-items", text: "Needle muted")
      expect(page).to have_no_css(".fps-tag-item", text: "needle-muted-tag")
    end

    it "leaves them out when switching the type of the full page search or pressing Enter" do
      visit("/search?q=needle")
      find(".search-types [data-search-type='categories_tags']").click
      expect(page).to have_css(".fps-tag-item", text: "needle-regular-tag")
      expect(page).to have_no_css(".category-items", text: "Needle muted")
      expect(page).to have_no_css(".fps-tag-item", text: "needle-muted-tag")

      find(".search-types [data-search-type='users']").click
      expect(page).to have_css(".fps-user-item", text: "needleother")
      expect(page).to have_no_css(".fps-user-item", text: "needleignored")

      search_page.clear_search_input
      search_page.type_in_search("needleign")
      search_page.search_input.send_keys(:enter)
      expect(page).to have_css(".search-results h3", text: I18n.t("js.search.no_results"))
      expect(page).to have_no_css(".fps-user-item", text: "needleignored")
    end

    it "leaves them out after @ and # in the box of the full page search" do
      visit("/search")
      search_page.type_in_search("@needle")
      expect(page).to have_css(".autocomplete.ac-user", text: "needleother")
      expect(page).to have_no_css(".autocomplete.ac-user", text: "needleignored")

      search_page.clear_search_input
      search_page.type_in_search("#needle")
      expect(page).to have_css(".autocomplete.ac-category-or-tag", text: "needle-regular-tag")
      expect(page).to have_no_css(".autocomplete.ac-category-or-tag", text: "needle-muted-tag")
      expect(page).to have_no_css(".autocomplete.ac-category-or-tag", text: "Needle muted")
    end

    it "still suggests ignored users for mentions in the composer" do
      visit("/new-topic")
      expect(composer).to be_opened
      composer.type_content("@needle")

      expect(page).to have_css(".autocomplete.ac-user", text: "needleignored")
      expect(page).to have_css(".autocomplete.ac-user", text: "needleother")
    end
  end

  describe "default muted and ignored users of a group" do
    let(:default_muted) do
      PageObjects::Components::SelectKit.new(".select-kit.mute-enhancements-default-muted-users")
    end
    let(:default_ignored_groups) do
      PageObjects::Components::SelectKit.new(".select-kit.mute-enhancements-default-ignored-groups")
    end
    let(:default_notifications_modal) { PageObjects::Modals::GroupDefaultNotifications.new }

    it "saves the defaults and applies them to current members when asked" do
      sign_in(admin)
      visit("/g/#{group.name}/manage/member-preferences")

      default_muted.expand
      default_muted.search(spammer.username)
      default_muted.select_row_by_value(spammer.username)
      default_muted.collapse

      find(".mute-enhancements-save-default-users").click
      default_notifications_modal.click_yes

      expect(page).to have_css(".mute-enhancements-save-default-users[disabled]")
      expect(MutedUser.where(user: member).pluck(:muted_user_id)).to contain_exactly(spammer.id)
      expect(DiscourseMuteEnhancements::GroupDefaultUsers.levels(group)).to eq(
        spammer.id => DiscourseMuteEnhancements::LEVELS[:mute],
      )

      page.refresh
      expect(default_muted).to have_selected_name(spammer.username)
    end

    it "saves default groups and applies them to current members when asked" do
      spam_group = Fabricate(:group, name: "spam_group")
      spam_group.add(spammer)

      sign_in(admin)
      visit("/g/#{group.name}/manage/member-preferences")

      default_ignored_groups.expand
      expect(default_ignored_groups).to have_no_option_value(group.id)
      default_ignored_groups.select_row_by_value(spam_group.id)
      default_ignored_groups.collapse

      find(".mute-enhancements-save-default-users").click
      default_notifications_modal.click_yes

      expect(page).to have_css(".mute-enhancements-save-default-users[disabled]")
      expect(DiscourseMuteEnhancements::GroupMutes.levels(member)).to eq(
        spam_group.id => DiscourseMuteEnhancements::LEVELS[:ignore],
      )
      expect(IgnoredUser.where(user: member).pluck(:ignored_user_id)).to contain_exactly(spammer.id)

      page.refresh
      expect(default_ignored_groups).to have_selected_name(spam_group.name)
    end

    it "is not shown to moderators who manage groups" do
      SiteSetting.moderators_manage_groups = true
      sign_in(Fabricate(:moderator))
      visit("/g/#{group.name}/manage/membership")

      expect(page).to have_css(".group-form-automatic-membership-automatic")
      expect(page).to have_no_css("a[href$='/manage/member-preferences']")

      visit("/g/#{group.name}/manage/member-preferences")
      expect(page).to have_current_path("/g/#{group.name}/manage/profile")
      expect(page).to have_no_css(".mute-enhancements-default-users")
    end
  end

  describe "the Member preferences tab of a group" do
    it "comes right after Membership" do
      sign_in(admin)
      visit("/g/#{group.name}/manage/profile")

      tabs = all(".user-secondary-navigation li a").map { |link| link[:href].split("/").last }
      expect(tabs.each_cons(2)).to include(%w[membership member-preferences])

      find(".user-secondary-navigation a[href$='/manage/member-preferences']").click
      expect(page).to have_css(".mute-enhancements-default-users")
      expect(page).to have_css(".mute-enhancements-hide-preferences")
      expect(page).to have_css(".mute-enhancements-muted-topics")
    end

    it "is not shown to group owners who are not site admins" do
      if SiteSetting.respond_to?(:enhanced_ignore_enabled)
        SiteSetting.enhanced_ignore_enabled = true
      end
      owner = Fabricate(:user)
      group.add_owner(owner)
      sign_in(owner)

      visit("/g/#{group.name}/manage/membership")
      expect(page).to have_css(".user-secondary-navigation a[href$='/manage/profile']")
      expect(page).to have_no_css("a[href$='/manage/member-preferences']")

      visit("/g/#{group.name}/manage/member-preferences")
      expect(page).to have_current_path("/g/#{group.name}/manage/profile")
      expect(page).to have_no_css(".mute-enhancements-member-preferences")
    end
  end

  describe "muting topics for a group's members" do
    fab!(:topic)
    fab!(:other_topic, :topic)

    def level(target) = TopicUser.find_by(user: member, topic: target)&.notification_level

    it "mutes the topics in the box for every member" do
      sign_in(admin)
      visit("/g/#{group.name}/manage/member-preferences")

      expect(page).to have_css(".mute-enhancements-save-muted-topics[disabled]")
      find("#mute-enhancements-muted-topics-input").fill_in(with: "#{topic.id}\n#{other_topic.id}")
      find(".mute-enhancements-save-muted-topics").click

      expect(page).to have_css(".mute-enhancements-save-muted-topics[disabled]")
      expect(page).to have_content(
        I18n.t("js.mute_enhancements.muted_topics.saved_and_applied", count: 1),
      )
      expect(level(topic)).to eq(TopicUser.notification_levels[:muted])
      expect(level(other_topic)).to eq(TopicUser.notification_levels[:muted])

      page.refresh
      expect(find("#mute-enhancements-muted-topics-input").value).to eq(
        "#{topic.id}\n#{other_topic.id}",
      )
    end

    it "shows what was wrong and keeps the box as it was typed" do
      sign_in(admin)
      visit("/g/#{group.name}/manage/member-preferences")

      find("#mute-enhancements-muted-topics-input").fill_in(with: "#{topic.id}\nabc")
      find(".mute-enhancements-save-muted-topics").click

      expect(page).to have_css(".dialog-body", text: "abc")
      expect(find("#mute-enhancements-muted-topics-input").value).to eq("#{topic.id}\nabc")
      expect(level(topic)).to be_nil
    end
  end

  describe "turning enhanced ignore on for a group's members" do
    before do
      skip("needs the enhanced-ignore plugin") if !SiteSetting.respond_to?(:enhanced_ignore_enabled)
      SiteSetting.enhanced_ignore_enabled = true
    end

    def preference(name) = User.find(member.id).custom_fields[name]

    it "turns each option on for every member with its box" do
      sign_in(admin)
      visit("/g/#{group.name}/manage/member-preferences")

      expect(page).to have_css(
        ".mute-enhancements-enhanced-ignore .control-label",
        text: I18n.t("js.mute_enhancements.enhanced_ignore.title"),
      )

      find(".mute-enhancements-enhanced-ignore-hide_ignored_topics").click
      expect(page).to have_content(
        I18n.t("js.mute_enhancements.enhanced_ignore.saved_and_applied", count: 1),
      )
      expect(page).to have_css(
        ".mute-enhancements-enhanced-ignore-hide_ignored_topics:checked:not([disabled])",
      )
      expect(preference("hide_ignored_topics")).to eq(true)
      expect(preference("ignored_user_cannot_reply_to_me")).to be_nil

      find(".mute-enhancements-enhanced-ignore-ignored_user_cannot_reply_to_me").click
      expect(page).to have_css(
        ".mute-enhancements-enhanced-ignore-ignored_user_cannot_reply_to_me:checked:not([disabled])",
      )
      expect(preference("ignored_user_cannot_reply_to_me")).to eq(true)

      page.refresh
      expect(page).to have_css(".mute-enhancements-enhanced-ignore-hide_ignored_topics:checked")
      expect(page).to have_css(
        ".mute-enhancements-enhanced-ignore-ignored_user_cannot_reply_to_me:checked",
      )
    end
  end

  describe "hiding preference pages from a group's members" do
    def hidden_pages = DiscourseMuteEnhancements::HiddenPreferences.group_pages(group)

    it "is set by admins with a box for each page" do
      sign_in(admin)
      visit("/g/#{group.name}/manage/member-preferences")

      find(".mute-enhancements-hide-preferences-users").click
      expect(page).to have_css(".mute-enhancements-hide-preferences-users:checked:not([disabled])")
      expect(hidden_pages).to eq(%w[users])

      find(".mute-enhancements-hide-preferences-tracking").click
      expect(page).to have_css(
        ".mute-enhancements-hide-preferences-tracking:checked:not([disabled])",
      )
      expect(hidden_pages).to eq(%w[tracking users])

      find(".mute-enhancements-hide-preferences-notifications").click
      expect(page).to have_css(
        ".mute-enhancements-hide-preferences-notifications:checked:not([disabled])",
      )
      expect(hidden_pages).to eq(%w[notifications tracking users])

      find(".mute-enhancements-hide-preferences-users").click
      expect(page).to have_css(
        ".mute-enhancements-hide-preferences-users:not(:checked):not([disabled])",
      )
      expect(hidden_pages).to eq(%w[notifications tracking])

      page.refresh
      expect(page).to have_css(".mute-enhancements-hide-preferences-notifications:checked")
      expect(page).to have_css(".mute-enhancements-hide-preferences-tracking:checked")
      expect(page).to have_css(".mute-enhancements-hide-preferences-users:not(:checked)")
    end

    it "hides the Notifications, Tracking and Users pages from members" do
      DiscourseMuteEnhancements::HiddenPreferences.update(group, %w[notifications tracking users])
      sign_in(member)

      visit("/u/#{member.username}/preferences/account")
      expect(page).to have_css(".user-nav__preferences-interface")
      expect(page).to have_no_css(".user-nav__preferences-notifications")
      expect(page).to have_no_css(".user-nav__preferences-tracking")
      expect(page).to have_no_css(".user-nav__preferences-users")

      %w[notifications users tracking tags].each do |hidden|
        visit("/u/#{member.username}/preferences/#{hidden}")
        expect(page).to have_current_path("/u/#{member.username}/preferences/account")
      end

      visit("/u/#{member.username}/preferences/interface")
      expect(page).to have_current_path("/u/#{member.username}/preferences/interface")
    end

    it "only hides the pages that were chosen" do
      DiscourseMuteEnhancements::HiddenPreferences.update(group, %w[users])
      sign_in(member)

      visit("/u/#{member.username}/preferences/tracking")
      expect(page).to have_current_path("/u/#{member.username}/preferences/tracking")
      expect(page).to have_css(".user-nav__preferences-notifications")
      expect(page).to have_css(".user-nav__preferences-tracking")
      expect(page).to have_no_css(".user-nav__preferences-users")
    end

    it "keeps the pages for everyone else" do
      DiscourseMuteEnhancements::HiddenPreferences.update(group, %w[tracking users])
      sign_in(user)

      visit("/u/#{user.username}/preferences/users")
      expect(page).to have_current_path("/u/#{user.username}/preferences/users")
      expect(page).to have_css(".user-nav__preferences-tracking")
    end

    context "with the user navigation in the sidebar" do
      before { SiteSetting.sidebar_user_navigation = true }

      def sidebar_link(name) = "[data-list-item-name='user-nav-preferences-#{name}']"

      it "hides the pages there too" do
        DiscourseMuteEnhancements::HiddenPreferences.update(group, %w[notifications tracking users])
        sign_in(member)

        visit("/u/#{member.username}/preferences/account")
        expect(page).to have_css(sidebar_link("account"))
        expect(page).to have_no_css(sidebar_link("notifications"))
        expect(page).to have_no_css(sidebar_link("tracking"))
        expect(page).to have_no_css(sidebar_link("users"))
      end

      it "keeps them for everyone else" do
        DiscourseMuteEnhancements::HiddenPreferences.update(group, %w[notifications tracking users])
        sign_in(user)

        visit("/u/#{user.username}/preferences/account")
        expect(page).to have_css(sidebar_link("notifications"))
        expect(page).to have_css(sidebar_link("tracking"))
        expect(page).to have_css(sidebar_link("users"))
      end
    end
  end
end
