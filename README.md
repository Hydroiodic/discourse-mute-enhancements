# discourse-search-tag-filter

在搜索结果中隐藏用户屏蔽的内容：

- 带有用户已设为免打扰的标签的话题；
- 用户已设为免打扰的类别里的话题；
- 用户已忽略或已设为免打扰的那些用户发的帖子，以及他们创建的话题。

顶部的快速搜索、完整搜索页、分页、`in:all`、`in:all-posts`、`order:` 等都会过滤；discourse-ai 的语义搜索（AI 搜索结果、AI 快速搜索）也会过滤。

## 通用规则

以下情况都不过滤：

- 在话题内搜索。
- 私信，包括 `in:messages` 和 `in:all` 结果里的私信。
- 匿名搜索。话题列表会对匿名用户应用 `default_tags_muted`、`default_categories_muted`，这里不应用：水源开启了 `login_required`，匿名搜索只来自站内的程序调用（例如 discourse-ai 的搜索工具），不应该因此少掉这些话题。

搜索结果里的标签、类别、用户、群组条目不受影响，例如搜用户名时仍会列出被忽略的用户。直接输入话题编号或链接搜索时，仍会返回那个话题。

## 免打扰的标签

话题只要带有用户设为免打扰的任何一个标签，就隐藏。以下情况不隐藏：

- 用户在搜索里明确要求的标签：在标签页内搜索（搜索上下文是这个标签）、`tags:`/`tag:` 过滤器（含同义词、`,` 和 `+` 写法）、`#标签` 和 `#标签组` 过滤器。只有这些标签不隐藏，话题上其他免打扰的标签照常生效。
- 用户关注了话题所在的类别，并且在个人设置里选择了“关注优先于免打扰”（`watched_precedence_over_muted`），和话题列表的行为一致。

“带有任何一个免打扰标签就隐藏”对应核心 `remove_muted_tags_from_latest` 的 `always`（默认值），不跟随这个设置变化。

## 免打扰的类别

隐藏范围和话题列表一致（核心的 `CategoryUser.muted_category_ids`）：

- 用户设为免打扰的类别；
- 这些类别的子类别，除非用户给子类别单独设置了其他级别；
- 打开 `mute_all_categories_by_default` 时，用户没有设置过级别的所有类别。

以下情况不隐藏：

- 搜索明确指定了类别：在类别页内搜索、`category:`/`categories:` 过滤器、`#类别` 过滤器。这时整个指定范围（包括子类别）都显示。
- 用户单独跟踪或关注了这个话题，和话题列表一致。
- 话题带有用户关注的标签，并且用户选择了“关注优先于免打扰”，和话题列表一致。

## 忽略和免打扰的用户

隐藏用户已忽略、已设为免打扰的那些用户发的帖子，以及他们创建的话题（包括别人在里面的回复：搜索结果会显示话题标题，标题是这些用户写的）。管理员和版主不会被隐藏：忽略的名单来自核心的 `IgnoredUser.ignored_ids_for`，和话题页隐藏帖子用的是同一个；免打扰的名单按同样的规则排除管理人员。

注意这比话题页严格：Discourse 里“免打扰”只屏蔽通知和私信，话题页仍会显示他们的帖子，只有“忽略”才会隐藏；搜索里两者都隐藏。可以用 `search_tag_filter_muted_users` 关掉免打扰用户这部分。

以下情况不隐藏：

- 搜索明确指定了这个用户：`@用户名`、`user:用户名` 过滤器，或在用户的个人活动页内搜索。只对指定的用户生效，其他被忽略或免打扰的用户照常隐藏。

## 实现

把 `DiscourseSearchTagFilter::SearchExtension` prepend 到 `::Search` 上，覆盖 `Search#apply_filters`：先调用 `super`，再依次加上三个过滤器的条件（`MutedTagsFilter`、`MutedCategoriesFilter`、`IgnoredUsersFilter`）。核心在 `Search#posts_query` 里调用 `apply_filters`，所有搜索帖子和话题的路径都经过这里；discourse-ai 的语义搜索也对自己的查询调用它。

为了判断用户明确要求了哪些标签和用户，`tags:`、`#`、`user:`、`@` 过滤器的正则和分词方式复制自核心 `lib/search.rb`；类别是否被明确指定，直接用核心过滤器设置的 `@category_filter_matched`（核心用它来显示搜索优先级为“忽略”的类别）。核心改动这些过滤器时需要同步。

已知不覆盖：discourse-image-enhancement 的“图片”搜索标签页走自己的 `/image-search/search` 接口，不经过 `Search`，结果里仍可能出现这些内容。

## 设置

- `search_tag_filter_enabled`：总开关，默认打开。
- `search_tag_filter_muted_tags`：隐藏免打扰的标签，默认打开。另外需要打开核心的 `tagging_enabled`。
- `search_tag_filter_muted_categories`：隐藏免打扰的类别，默认打开。
- `search_tag_filter_ignored_users`：隐藏忽略的用户，默认打开。
- `search_tag_filter_muted_users`：隐藏免打扰的用户，默认打开。

## 安装

按 Discourse 插件的通常方式安装：https://meta.discourse.org/t/install-a-plugin/19157
