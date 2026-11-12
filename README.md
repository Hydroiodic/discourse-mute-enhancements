# discourse-search-tag-filter

在搜索结果中隐藏带有用户已屏蔽标签的话题。

## 行为

话题只要带有当前用户屏蔽的任何一个标签，就不会出现在搜索结果里。顶部的快速搜索、完整搜索页、分页、`in:all`、`in:all-posts`、`order:` 等都会过滤；discourse-ai 的语义搜索（AI 搜索结果、AI 快速搜索）也会过滤。

以下情况不过滤：

- 用户在搜索里明确要求的标签：在标签页内搜索（搜索上下文是这个标签）、`tags:`/`tag:` 过滤器（含同义词、`,` 和 `+` 写法）、`#标签` 和 `#标签组` 过滤器。只有这些标签不过滤，话题上其他被屏蔽的标签照常过滤。
- 用户关注了话题所在的分类，并且在个人设置里选择了“关注优先于屏蔽”（`watched_precedence_over_muted`），和话题列表的行为一致。
- 在话题内搜索。
- 私信，包括 `in:messages` 和 `in:all` 结果里的私信。
- 匿名搜索。话题列表会对匿名用户应用 `default_tags_muted`，这里不应用：水源开启了 `login_required`，匿名搜索只来自站内的程序调用（例如 discourse-ai 的搜索工具），不应该因此少掉这些话题。

搜索结果里的标签、分类、用户、群组条目不受影响。直接输入话题编号或链接搜索时，仍会返回那个话题。

“带有任何一个屏蔽标签就隐藏”对应核心 `remove_muted_tags_from_latest` 的 `always`（默认值），不跟随这个设置变化。

已知不覆盖：discourse-image-enhancement 的“图片”搜索标签页走自己的 `/image-search/search` 接口，不经过 `Search`，结果里仍可能出现带屏蔽标签的话题。

## 实现

把 `DiscourseSearchTagFilter::SearchExtension` prepend 到 `::Search` 上，覆盖 `Search#apply_filters`：先调用 `super`，再加一个 `NOT EXISTS (topic_tags ...)` 条件。核心在 `Search#posts_query` 里调用它，所有搜索帖子和话题的路径都经过这里；discourse-ai 的语义搜索也对自己的查询调用它。

`tags:` 和 `#` 过滤器的正则、分词方式复制自核心 `lib/search.rb`，用来判断哪些标签是用户明确要求的。核心改动这两个过滤器时需要同步。

## 设置

- `search_tag_filter_enabled`：是否启用，默认打开。另外需要打开核心的 `tagging_enabled`。

## 安装

按 Discourse 插件的通常方式安装：https://meta.discourse.org/t/install-a-plugin/19157
