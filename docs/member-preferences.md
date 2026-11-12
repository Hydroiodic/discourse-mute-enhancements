# 群组的“成员偏好”页面

插件在群组 → 管理 里加了一个“成员偏好”标签，紧跟在“成员资格”后面，里面是这几项设置：

- [群组默认屏蔽的用户和群组](group-defaults.md)
- [对群组成员隐藏个人设置页面](hide-preferences.md)
- [给群组成员屏蔽的话题](group-muted-topics.md)
- [给群组成员打开增强屏蔽](group-enhanced-ignore.md)

只有网站管理员能看到这个标签；群组拥有者和版主看不到，直接打开它的地址会转到“资料”。自动群组没有这个标签。

核心没有给群组管理页加标签的插件接口，插件改写了核心 `controller:group.manage` 的 `tabs`，并给 `/g/群组名/manage/member-preferences` 加了服务端路由。
