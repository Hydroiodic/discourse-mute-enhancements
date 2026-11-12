# 数据存在哪里

插件没有数据库迁移，不建自己的表，数据都存在核心已有的表里：

- 用户免打扰、忽略的群组，以及哪些免打扰、忽略记录是群组带来的，存在 `plugin_store_rows`（核心给插件存数据用的 PluginStore），每个用户每种一行 JSON，键是 `group_mutes:用户ID`、`derived_mutes:用户ID`、`derived_ignores:用户ID`（`DiscourseMuteEnhancements::UserStore`）。每次写入都在一条 SQL 里增删 JSON 的键，同时写同一行不会互相覆盖。没有放在用户的自定义字段里，是因为核心保存用户自定义字段时，会按它先前读到的内容把这个用户的字段整体写回，可能删掉插件在这期间写入的记录；读用户自定义字段时也会一次读出这个用户的所有行。
- 群组的设置存在群组的自定义字段里：默认屏蔽的用户 `mute_enhancements_default_users` 和群组 `mute_enhancements_default_groups`（JSON），隐藏的个人设置页面 `mute_enhancements_hide_preferences`，屏蔽的话题 `mute_enhancements_muted_topics`，增强屏蔽选项 `mute_enhancements_enhanced_ignore`。
- 免打扰、忽略本身写在核心的 `muted_users`、`ignored_users` 里，见[免打扰和忽略群组](group-mutes.md)。
