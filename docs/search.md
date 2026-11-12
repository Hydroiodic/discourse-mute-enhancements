# 搜索

用户设为免打扰或忽略的标签、类别、用户、话题，在搜索结果里看不到。

隐藏的内容：

- 带有用户已设为免打扰的标签的话题；
- 用户已设为免打扰的类别里的话题；
- 用户已设为免打扰的话题；
- 用户已忽略或已设为免打扰的那些用户发的帖子，以及他们创建的话题；
- 搜索结果的用户、类别、标签部分里的这些用户、类别、标签；
- 搜索框里输入 `@`、`#` 时联想出的这些用户、类别、标签，以及完整搜索页“用户”“类别/标签”类型里的它们，见[联想](#联想和完整搜索页的用户类别标签类型)。

顶部的快速搜索、完整搜索页、分页、`in:all`、`in:all-posts`、`order:` 等都会过滤；discourse-ai 的语义搜索（AI 搜索结果、AI 快速搜索）也会过滤。每一类都可以在[设置](settings.md)里单独关掉。

## 通用规则

以下情况都不过滤：

- 在话题内搜索。
- 私信，包括 `in:messages` 和 `in:all` 结果里的私信。
- 匿名搜索。话题列表会对匿名用户应用 `default_tags_muted`、`default_categories_muted`，这里不应用：水源开启了 `login_required`，匿名搜索只来自站内的程序调用（例如 discourse-ai 的搜索工具），不应该因此少掉这些话题。

直接输入话题编号或链接搜索时，仍会返回那个话题。

## 免打扰的标签

话题只要带有用户设为免打扰的任何一个标签，就隐藏。以下情况不隐藏话题：

- 用户在搜索里明确要求的标签：在标签页内搜索（搜索上下文是这个标签）、`tags:`/`tag:` 过滤器（含同义词、`,` 和 `+` 写法）、`#标签` 和 `#标签组` 过滤器。只有这些标签不隐藏，话题上其他免打扰的标签照常生效。
- 用户关注了话题所在的类别，并且在个人设置里选择了“关注优先于免打扰”（`watched_precedence_over_muted`），和话题列表的行为一致。

“带有任何一个免打扰标签就隐藏”对应核心 `remove_muted_tags_from_latest` 的 `always`（默认值），不跟随这个设置变化。

搜索结果的标签部分不显示免打扰的标签，没有例外。

## 免打扰的类别

隐藏范围和话题列表一致（核心的 `CategoryUser.muted_category_ids`）：

- 用户设为免打扰的类别；
- 这些类别的子类别，除非用户给子类别单独设置了其他级别；
- 打开 `mute_all_categories_by_default` 时，用户没有设置过级别的所有类别。

以下情况不隐藏话题：

- 搜索明确指定了类别：在类别页内搜索、`category:`/`categories:` 过滤器、`#类别` 过滤器。这时整个指定范围（包括子类别）都显示。
- 用户单独跟踪或关注了这个话题，和话题列表一致。
- 话题带有用户关注的标签，并且用户选择了“关注优先于免打扰”，和话题列表一致。

搜索结果的类别部分不显示这些类别，没有例外。

## 免打扰的话题

话题的通知级别是“免打扰”时，整个话题（包括里面的回复）都不出现在搜索结果里，包括[群组给成员屏蔽的话题](group-muted-topics.md)。核心的搜索默认不排除这些话题（只有 `in:watching`、`in:tracking` 这种主动筛选），话题列表才会排除。

以下情况不隐藏：

- 在这个话题内搜索，包括用 `topic:话题编号` 过滤器（核心会把它当作在话题内搜索）。
- 直接输入话题编号或链接搜索（见上面的通用规则）。
- 把通知级别改回别的级别之后。

## 忽略和免打扰的用户

隐藏用户已忽略、已设为免打扰的那些用户发的帖子，以及他们创建的话题（包括别人在里面的回复：搜索结果会显示话题标题，标题是这些用户写的）。管理员和版主不会被隐藏：忽略的名单来自核心的 `IgnoredUser.ignored_ids_for`，和话题页隐藏帖子用的是同一个；免打扰的名单按同样的规则排除管理人员。

注意这比话题页严格：Discourse 里“免打扰”只屏蔽通知和私信，话题页仍会显示他们的帖子，只有“忽略”才会隐藏；搜索里两者都隐藏。可以用 `mute_enhancements_search_muted_users` 关掉免打扰用户这部分。

以下情况不隐藏帖子：

- 搜索明确指定了这个用户：`@用户名`、`user:用户名` 过滤器，或在用户的个人活动页内搜索。只对指定的用户生效，其他被忽略或免打扰的用户照常隐藏。

搜索结果的用户部分不显示这些用户（管理员和版主除外），没有例外。

## 联想和完整搜索页的“用户”“类别/标签”类型

搜索框（顶部的搜索菜单和完整搜索页的输入框）里输入 `@` 或 `#` 时弹出的用户、类别、标签联想不经过 `Search`：用户和标签分别查 `/u/search/users`、`/tags/filter/search`，类别在浏览器里查。完整搜索页的“用户”“类别/标签”类型也是用这几种方式查的，不是 `Search` 的结果。插件让它们和搜索结果的用户、类别、标签部分一样：

- 不出现忽略、免打扰的用户，管理员和版主除外。`@` 后面还没输入时列出的最近活跃用户也一样。
- 不出现免打扰的类别，范围同上（包括子类别和 `mute_all_categories_by_default`）。
- 不出现免打扰的标签。
- 没有例外；跟随[设置](settings.md)里的 `mute_enhancements_search_*`。匿名用户不过滤。

发帖编辑器和聊天里的 `@` 提及、`#` 联想，用户和标签选择框（例如私信收件人、话题的标签、完整搜索页高级搜索里的选择框），以及用户名录（`/u`），仍然列出所有人和所有类别、标签，以免想提及、选择的时候找不到。

## 实现

把 `DiscourseMuteEnhancements::SearchExtension` prepend 到 `::Search` 上：

- 覆盖 `Search#apply_filters`：先调用 `super`，再依次加上四个过滤器的条件（`MutedTagsFilter`、`MutedCategoriesFilter`、`MutedTopicsFilter`、`IgnoredUsersFilter`）。核心在 `Search#posts_query` 里调用 `apply_filters`，所有搜索帖子和话题的路径都经过这里；discourse-ai 的语义搜索也对自己的查询调用它。
- 覆盖 `user_search`、`category_search`、`tags_search`：在 `User`/`Category.where.not(id: ...).scoping { super() }` 里调用核心的方法，不复制核心的查询。`category_search` 进入 scoping 之前先算好 `secure_category_ids`，因为 Guardian 会缓存它，而它本身要查 `Category`。标签用 `Tag.where("tags.id NOT IN (?)", ...)`：核心的 `Tag.visible` 会 `merge` 一个自带 `tags.id` 条件的查询，`merge` 会替换掉同一列上已有的条件，写成 SQL 字符串才不会被丢掉。

为了判断用户明确要求了哪些标签和用户，`tags:`、`#`、`user:`、`@` 过滤器的正则和分词方式复制自核心 `lib/search.rb`；类别是否被明确指定，直接用核心过滤器设置的 `@category_filter_matched`（核心用它来显示搜索优先级为“忽略”的类别）。核心改动这些过滤器时需要同步。

联想用的接口发帖编辑器、聊天、选择框也在用，而且聊天里的 `@` 提及发出的参数和搜索框完全一样，服务器分不出来。所以由浏览器标记来自搜索的请求（`assets/javascripts/discourse/lib/search-suggestions.js`），服务器只过滤带标记的请求（`lib/discourse_mute_enhancements/search_suggestions.rb`）：

- 来自搜索的请求：焦点在搜索框里（`.search-menu-container`、`.search-bar__field`）时发出的；或者完整搜索页正按“用户”“类别/标签”类型搜索，而请求的关键词就是页面的搜索词。后一种在发请求时直接读 `full-page-search` 控制器的 `searching`、`search_type`、`searchTerm`：核心搜索前设上 `searching`，结果回来后清掉，所以不管是按回车、点搜索按钮、切换类型还是打开链接开始的搜索都能认出来。核心的 `_search` 用了 `@bind`，第一次经过 `super._search` 时会把绑定好的核心方法直接写到实例上，之后的调用都绕过子类，所以不能靠覆盖 `_search` 来记搜索词。
- 用户和标签：用 `$.ajaxPrefilter` 给这两个接口的请求加上 `mute_enhancements_search=true`。服务器把 `UsersControllerExtension` prepend 到 `UsersController`，在 `User.where.not(id: ...).scoping { super() }` 里调用核心的 `search_users`（`UserSearch` 的查询都从 `User` 开始）；把 `TagsControllerExtension` prepend 到 `TagsController`，把免打扰的标签加进 `selected_tag_ids`，核心本来就会把已选的标签排除在结果外。带 `filterForInput` 的请求（标签选择框）不加：这时 `selected_tag_ids` 还会被当作父标签、影响标签组“每个话题只能选一个”的规则。
- 类别：包装 `Category.search`，多取一些再去掉免打扰的类别。插件 API 没有修改模型静态方法的办法，`modifyClass` 用在模型上也已弃用，所以直接替换。免打扰的类别取自核心发给浏览器的 `muted_category_ids`、`indirectly_muted_category_ids`，用户修改类别级别时会即时更新；`mute_all_categories_by_default` 带来的那部分不在这两个列表里，插件另外在当前用户上加了 `mute_enhancements_default_muted_category_ids`，这部分刷新页面后才更新。
- 浏览器按参数把用户联想的结果缓存 30 秒，搜索框和聊天提及的参数相同，所以焦点进出搜索框时清空这个缓存，免得一边用上另一边的结果。

已知不覆盖：discourse-image-enhancement 的“图片”搜索标签页走自己的 `/image-search/search` 接口，不经过 `Search`，结果里仍可能出现这些内容。
