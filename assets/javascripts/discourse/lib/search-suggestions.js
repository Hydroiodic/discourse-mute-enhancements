import $ from "jquery";
import getURL from "discourse/lib/get-url";
import { resetUserSearchCache } from "discourse/lib/user-search";
import Category from "discourse/models/category";

// The search box suggests users after `@` (/u/search/users), and categories and tags after `#`
// (categories in the browser with Category.search, tags from /tags/filter/search). The full page
// search's "users" and "categories/tags" types use the same lookups. So do mentions in the
// composer and chat and the user and tag choosers, which should still list everyone. Core passes
// no options through to these lookups that would tell them apart, so lookups count as made from
// search when the focus is in a search box, or when they are for the term of a full page search
// of those two types. Those lookups leave out what the user muted or ignored: the server leaves
// out users and tags when the request has PARAM (see SearchSuggestions in the plugin's lib), and
// categories are left out here.

const PARAM = "mute_enhancements_search";

// The search menu, in the header and elsewhere, and the input of the full page search.
const SEARCH_BOX_SELECTOR = ".search-menu-container, .search-bar__field";

// Full page search types that look up users, or categories and tags, instead of posts.
const PAGE_SEARCH_TYPES = ["users", "categories_tags"];

let currentUser = null;
let pageSearchTerm = null;
let focusInSearchBox = false;
let installed = false;

function inSearchBox(element) {
  return !!element?.closest?.(SEARCH_BOX_SELECTOR);
}

// The lookups drop the leading `@` of a username, so compare without it.
function normalize(term) {
  return String(term ?? "")
    .trim()
    .replace(/^[@#]/, "")
    .toLowerCase();
}

function fromSearch(term) {
  if (!currentUser) {
    return false;
  }
  if (inSearchBox(document.activeElement)) {
    return true;
  }
  return (
    pageSearchTerm !== null && normalize(pageSearchTerm) === normalize(term)
  );
}

function lookupTermKey(url) {
  const path = String(url ?? "")
    .split("?")[0]
    .replace(/\.json$/, "");
  if (path === getURL("/u/search/users")) {
    return "term";
  }
  if (path === getURL("/tags/filter/search")) {
    return "q";
  }
}

// The data may still be an object when prefilters run, so the marker goes on the URL; jQuery adds
// the data after it.
function markLookup(options, originalOptions) {
  const key = lookupTermKey(options.url);
  if (!key || !fromSearch(originalOptions.data?.[key])) {
    return;
  }
  options.url += `${options.url.includes("?") ? "&" : "?"}${PARAM}=true`;
}

// Present when the search hides muted categories. Core keeps muted_category_ids and
// indirectly_muted_category_ids current when the user changes a category's level.
function hiddenCategoryIds() {
  const byDefault = currentUser?.mute_enhancements_default_muted_category_ids;
  if (!byDefault) {
    return [];
  }
  return [
    ...byDefault,
    ...(currentUser.muted_category_ids ?? []),
    ...(currentUser.indirectly_muted_category_ids ?? []),
  ];
}

// There is no plugin API for a model's static methods (api.modifyClass on models is
// deprecated), so Category.search is wrapped directly. In core, only the category and tag
// lookup above calls it.
function wrapCategorySearch() {
  const search = Category.search;

  Category.search = function (term, opts) {
    const hidden = hiddenCategoryIds();
    if (!hidden.length || opts?.limit === 0 || !fromSearch(term)) {
      return search.call(this, term, opts);
    }

    // Ask for as many more as could be left out, so that up to `limit` remain.
    const limit = opts?.limit || 5;
    return search
      .call(this, term, { ...opts, limit: limit + hidden.length })
      .filter((category) => !hidden.includes(category.id))
      .slice(0, limit);
  };
}

// The user lookup caches results by its parameters for 30 seconds, and the search box sends the
// same parameters as chat mentions. Clearing the cache when the focus moves into or out of a
// search box keeps either one from showing the other's results.
function onFocusIn(event) {
  const inSearch = inSearchBox(event.target);
  if (inSearch !== focusInSearchBox) {
    focusInSearchBox = inSearch;
    resetUserSearchCache();
  }
}

export default function setupSearchSuggestions(api) {
  currentUser = api.getCurrentUser();
  pageSearchTerm = null;

  if (!currentUser) {
    return;
  }

  api.modifyClass(
    "controller:full-page-search",
    (Superclass) =>
      class extends Superclass {
        // Category.search runs during _search and the user and tag lookups shortly after it, so
        // the term is recorded first.
        _search() {
          pageSearchTerm = PAGE_SEARCH_TYPES.includes(this.search_type)
            ? this.searchTerm
            : null;
          return super._search(...arguments);
        }
      }
  );

  const router = api.container.lookup("service:router");
  api.onPageChange(() => {
    if (router.currentRouteName !== "full-page-search") {
      pageSearchTerm = null;
    }
  });

  // Prefilters cannot be removed, so they and the wrapper are installed once and read the state
  // above, which each boot of the app resets.
  if (!installed) {
    installed = true;
    $.ajaxPrefilter(markLookup);
    wrapCategorySearch();
    document.addEventListener("focusin", onFocusIn);
  }
}
