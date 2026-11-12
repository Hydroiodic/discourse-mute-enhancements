# frozen_string_literal: true

module DiscourseMuteEnhancements
  # Base class for the settings on a group's Manage > Member preferences page. Only admins can
  # change them, automatic groups do not have them, and each is turned off by its own site
  # setting, which subclasses check through #feature.
  class GroupSettingsController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_admin
    before_action :ensure_feature_enabled
    before_action :find_group

    private

    # The module that implements the setting; it must respond to enabled?.
    def feature
      raise NotImplementedError
    end

    def ensure_feature_enabled
      raise Discourse::NotFound if !feature.enabled?
    end

    def find_group
      @group = Group.find(params.require(:group_id))
      raise Discourse::InvalidParameters.new(:group_id) if @group.automatic
    end
  end
end
