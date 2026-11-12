# discourse-mute-enhancements

增强 Discourse 的免打扰和忽略：搜索里不再出现免打扰、忽略的内容，用户可以免打扰、忽略整个群组，管理员可以给群组成员统一设置屏蔽。

| 功能 | 说明 |
| --- | --- |
| [搜索](docs/search.md) | 免打扰、忽略的标签、类别、用户、话题不出现在搜索结果和 `@`、`#` 联想里 |
| [隐藏群组的 group_users](docs/hidden-group-users.md) | 用户资料接口不再暴露用户看不到的群组 |
| [免打扰和忽略群组](docs/group-mutes.md) | 把整个群组设为免打扰或忽略，成员随之被免打扰或忽略 |
| [群组的“成员偏好”页面](docs/member-preferences.md) | 群组 → 管理 里给管理员用的页面，下面四项都在这里 |
| [群组默认屏蔽的用户和群组](docs/group-defaults.md) | 新成员加入时自动免打扰、忽略指定的用户和群组 |
| [对群组成员隐藏个人设置页面](docs/hide-preferences.md) | 群组成员看不到个人设置的“通知”“跟踪”“用户”页面 |
| [给群组成员屏蔽的话题](docs/group-muted-topics.md) | 把指定话题对群组成员设为免打扰 |
| [给群组成员打开增强屏蔽](docs/group-enhanced-ignore.md) | 给群组成员打开 [enhanced-ignore](https://github.com/ShuiyuanSJTU/enhanced-ignore) 的增强屏蔽选项 |
| [设置](docs/settings.md) | 站点设置，默认都打开 |
| [数据存在哪里](docs/data-storage.md) | 插件没有自己的表，数据存在核心的表里 |

## 安装

按 Discourse 插件的通常方式安装：https://meta.discourse.org/t/install-a-plugin/19157 。插件没有数据库迁移。
