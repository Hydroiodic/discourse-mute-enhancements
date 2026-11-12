# frozen_string_literal: true

DiscourseMuteEnhancements::Engine.routes.draw do
  scope "/groups/:group_id", constraints: { group_id: /\d+/ } do
    put "/default-users" => "group_default_users#update"
    put "/hide-preferences" => "group_hide_preferences#update"
    put "/muted-topics" => "group_muted_topics#update"
    put "/enhanced-ignore" => "group_enhanced_ignore#update"
  end
end

Discourse::Application.routes.draw do
  mount DiscourseMuteEnhancements::Engine, at: "mute-enhancements"

  # Lets the browser open Group > Manage > Member preferences directly, like core's other tabs.
  %w[groups g].each do |root_path|
    get "#{root_path}/:name/manage/member-preferences" => "groups#show",
        :constraints => {
          name: RouteFormat.username,
        }
  end
end
