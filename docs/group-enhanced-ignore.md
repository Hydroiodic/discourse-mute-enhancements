# 给群组成员打开增强屏蔽

[enhanced-ignore](https://github.com/ShuiyuanSJTU/enhanced-ignore) 插件在 个人设置 → 通知 里有“增强屏蔽”两个选项，默认关闭，要用户自己勾选：“不在我的主题列表中显示被屏蔽用户发表的话题帖”（最新、新话题、未读、类别、标签等话题列表里不再出现用户忽略的人发的话题），“被屏蔽用户不能回复我的话题帖”（被忽略的人不能回复用户发的话题，帖子数达到 `disable_topic_cannot_reply_threshold` 的话题除外）。

群组 → 管理 → [成员偏好](member-preferences.md) 页面的“增强屏蔽”照搬这两个选项，“不在成员的主题列表中显示被屏蔽用户发表的话题帖”和“被屏蔽用户不能回复成员的话题帖”，分别设置，默认都不勾选，改动立即保存。

- 勾上一项时，所有现有成员的这一项都打开，包括自己关掉过的；已经勾着的不会再改一次。以后加入群组的成员，加入时群组勾选的选项都会打开。
- 成员可以在 个人设置 → 通知 里自己关掉。取消勾选、退出群组，都不会关掉已经打开的选项。要让成员在界面上关不掉，再对成员[隐藏“通知”页面](hide-preferences.md)。
- 被忽略的用户包括群组默认忽略的用户和群组成员（见[群组默认屏蔽的用户和群组](group-defaults.md)），所以两者一起用，可以让群组成员在话题列表里看不到指定用户的话题、也不让他们回复。直接打开话题时仍能看到首帖，这是核心的行为。
- 需要安装并打开 enhanced-ignore（`enhanced_ignore_enabled`），否则页面上没有这一节，插件也不会改用户的选项。
- 只有管理员能看到和修改，改动时记一条管理日志。
- 写的是 enhanced-ignore 的用户自定义字段 `hide_ignored_topics` 和 `ignored_user_cannot_reply_to_me`；群组勾选的选项存在群组的自定义字段 `mute_enhancements_enhanced_ignore` 里，逗号分隔（`DiscourseMuteEnhancements::GroupEnhancedIgnore`）。
