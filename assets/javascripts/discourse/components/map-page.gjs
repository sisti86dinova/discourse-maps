// ============================================================================
//  Discourse Maps - /map page component.
//
//  Shows:
//    1. at the top, the filters (category + tags, only those actually
//       present among the listed topics, to avoid filtering to nothing);
//    2. an interactive map with a pin for each geolocated topic (popup
//       with title, category, tags and a link to the topic);
//    3. below, the list of matching topics (ordered by descending
//       creation date), loaded in groups of 10 while scrolling.
//
//  Arguments:
//    @topics          - array of topics ({ id, title, fancy_title, url,
//                       category_id, tags, location, ... }) from the /map
//                       route, already ordered by the server (most recent first).
//    @filters          - { category_ids: [...], tags: [{id, name}, ...],
//                        countries: [{id, name}, ...] }, filter options
//                        computed by the server based on the topics that
//                        can actually be shown.
//    @categoryId      - id of the currently selected category (filter).
//    @selectedTags    - array of the currently selected tags (filter).
//    @countryName     - currently selected country (filter).
//    @year/@month/@day - currently selected period (filter, hierarchical:
//                       month only makes sense with a year, day only with
//                       year+month).
//    @onChangeCategory - callback(categoryId) when the category filter changes.
//    @onChangeTags     - callback(tags[]) when the tag filter changes.
//    @onChangeCountry  - callback(countryName) when the country filter changes.
//    @onChangeYear/@onChangeMonth/@onChangeDay - callback(value) when the
//                       respective period filter level changes.
//    @onResetDate      - callback() that clears the period filter (used by
//                       "Remove filters").
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { htmlSafe } from "@ember/template";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { i18n } from "discourse-i18n";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import ComboBox from "discourse/select-kit/components/combo-box";
import DiscourseMapsDateFilter from "./discourse-maps-date-filter";
import DiscourseMapsMap from "./discourse-maps-map";
import formatDateRange, {
  formatDateParts,
} from "../lib/discourse-maps-date-range";

// How many topics to show at a time in the list (scroll loading).
const PAGE_SIZE = 10;

// Fallback color for the map pin when the topic has no category (or the
// category has no color).
const DEFAULT_MARKER_COLOR = "#0088CC";

// Thresholds for the relative format (seconds -> unit), same approach as
// the MDN recipe for Intl.RelativeTimeFormat: no external dependency, so
// no risk of inheriting an "Invalid date" from other utilities.
const RELATIVE_TIME_DIVISIONS = [
  { amount: 60, unit: "second" },
  { amount: 60, unit: "minute" },
  { amount: 24, unit: "hour" },
  { amount: 7, unit: "day" },
  { amount: 4.34524, unit: "week" },
  { amount: 12, unit: "month" },
  { amount: Number.POSITIVE_INFINITY, unit: "year" },
];

export default class MapPage extends Component {
  @service site;
  @service siteSettings;
  @service currentUser;
  @service composer;

  @tracked visibleCount = PAGE_SIZE;

  // On mobile the filters are enclosed in a collapsible block, closed by
  // default: they open with the "Filters" button below the title. On
  // desktop the button is hidden via CSS and the filters are always visible.
  @tracked filtersExpanded = false;

  observer = null;

  // New result from the server (new filters): pagination starts over.
  // Run from {{didUpdate}}, outside the render tracking cycle, to avoid
  // Ember's backtracking error.
  resetPaging = () => {
    this.visibleCount = PAGE_SIZE;
  };

  // Returns the category (with url and name) given its id (or null).
  category(categoryId) {
    if (!categoryId) {
      return null;
    }
    return this.site.categories?.find((c) => c.id === categoryId) || null;
  }

  // Categories to offer in the filter: only those present among the
  // topics that can be shown (given by the server), not all the forum's categories.
  get availableCategories() {
    const ids = this.args.filters?.category_ids || [];
    return (this.site.categories || [])
      .filter((c) => ids.includes(c.id))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  // Category ComboBox rows: when the category has an icon (icon badge
  // style), select-kit draws a <svg><use href="#name"></use></svg> inside
  // the row (.select-kit-row), but with no color at all: here we generate
  // a CSS rule per row (scoped on data-value, the category's id) that
  // colors that icon with the category's native color. Nothing to
  // validate on the id (it's always a number); the color, on the other
  // hand, comes from Discourse's admin, so we still check it before
  // interpolating it into CSS.
  get categoryRowIconStyles() {
    const rules = this.availableCategories
      .filter((c) => /^[0-9a-fA-F]{3,8}$/.test(c.color || ""))
      .map(
        (c) =>
          `.discourse-maps-filters__category .select-kit-row[data-value="${c.id}"] svg use { fill: #${c.color}; }`
      )
      .join("\n");
    return htmlSafe(rules);
  }

  // Value for the category ComboBox: @categoryId comes from the query
  // string (so always as a string), but category ids are numbers.
  // Without this conversion the ComboBox doesn't find the matching row
  // and shows the id instead of the name. If the id is no longer among
  // the available ones we return null instead of showing a value that
  // can't be resolved.
  get categoryIdValue() {
    const raw = this.args.categoryId;
    if (raw === null || raw === undefined || raw === "") {
      return null;
    }
    const id = Number(raw);
    return this.availableCategories.some((c) => c.id === id) ? id : null;
  }

  // Tags to offer in the filter: only those present among the topics that
  // can be shown (given by the server as { id, name } objects). They must
  // be passed this way (not simplified to an array of plain strings)
  // because the ComboBox:
  //  - deduplicates the content internally using item[valueProperty]: on
  //    plain strings that key is always undefined for each of them (it
  //    would collapse them all into a single entry);
  //  - if valueProperty is disabled to avoid the dedup, the selected
  //    value becomes an array (content.filter(...)) instead of a single
  //    item, and the label no longer resolves (it stays empty).
  // With @valueProperty="name" in the template, the dedup and comparison
  // key is the name (unique per row): neither problem shows up.
  get availableTags() {
    return this.args.filters?.tags || [];
  }

  // Only one tag selectable at a time, like the category. We return null
  // if the tag is no longer among the available ones.
  get selectedTagName() {
    const name = (this.args.selectedTags && this.args.selectedTags[0]) || null;
    return name && this.availableTags.some((t) => t.name === name) ? name : null;
  }

  // Countries to offer in the filter: only those present among the
  // topics that can be shown (given by the server as { id, name }
  // objects), for the same reason as the tags (above).
  get availableCountries() {
    return this.args.filters?.countries || [];
  }

  // Selected country: null if it's no longer among the available ones.
  get selectedCountryName() {
    const name = this.args.countryName || null;
    return name && this.availableCountries.some((c) => c.name === name) ? name : null;
  }

  // A filter is "active" based on the state passed by the route (URL),
  // not on what the ComboBox manages to show: otherwise, if the selected
  // value is no longer among the available options, the filter would
  // still be active (topics remain filtered) but the reset button would
  // stay disabled.
  get hasActiveFilters() {
    return (
      Boolean(this.args.categoryId) ||
      Boolean(this.args.selectedTags && this.args.selectedTags.length) ||
      Boolean(this.args.countryName) ||
      Boolean(this.args.year)
    );
  }

  // How many filters are active: shown on the mobile toggle button, so
  // the user knows filters are applied even with the block closed. The
  // period (year/month/day) counts as a single filter, regardless of its
  // level of detail.
  get activeFilterCount() {
    let count = 0;
    if (this.args.categoryId) {
      count++;
    }
    if (this.args.selectedTags && this.args.selectedTags.length) {
      count++;
    }
    if (this.args.countryName) {
      count++;
    }
    if (this.args.year) {
      count++;
    }
    return count;
  }

  get filtersToggleLabel() {
    const base = i18n("discourse_maps.filters.toggle");
    return this.activeFilterCount ? `${base} (${this.activeFilterCount})` : base;
  }

  toggleFilters = () => {
    this.filtersExpanded = !this.filtersExpanded;
  };

  // The ComboBox is configured with a "none" option (label "All
  // categories"/"Tags"/"Countries") to deselect the filter. With
  // @valueProperty="name" (tags and country) that option ends up with
  // the same valueProperty and nameProperty ("name"): select-kit ends up
  // reporting the translated label as the value instead of null (a known
  // bug in its internal defaultItem utility, which overwrites the value
  // when the two properties coincide). By validating the value against
  // the list of available options, a value that doesn't match any of
  // them (including that spurious label) is treated as "no filter"
  // instead of ending up in the query string.
  handleCategoryChange = (value) => {
    const categoryId = Number(value);
    const isValid = this.availableCategories.some((c) => c.id === categoryId);
    this.args.onChangeCategory(isValid ? categoryId : null);
  };

  handleTagChange = (value) => {
    const isValid = this.availableTags.some((t) => t.name === value);
    this.args.onChangeTags(isValid ? [value] : []);
  };

  handleCountryChange = (value) => {
    const isValid = this.availableCountries.some((c) => c.name === value);
    this.args.onChangeCountry(isValid ? value : null);
  };

  // Years available in the period filter: options computed by the server
  // on the topics that can be shown, with the category/tag/country
  // filters already applied.
  get availableYears() {
    return this.args.filters?.years || [];
  }

  // @year comes from the query string (always a string): same treatment
  // as categoryIdValue, to make the value match the numeric type
  // expected by the ComboBox.
  get selectedYear() {
    const raw = this.args.year;
    if (raw === null || raw === undefined || raw === "") {
      return null;
    }
    const year = Number(raw);
    return this.availableYears.some((y) => y.id === year) ? year : null;
  }

  // Available months (depend on the selected year, see plugin.rb): the
  // month name is localized client-side with Intl, the server only
  // returns the number (1-12).
  get availableMonths() {
    const months = this.args.filters?.months || [];
    const formatter = new Intl.DateTimeFormat(
      document.documentElement.lang || undefined,
      { month: "long" }
    );
    return months.map((m) => ({
      id: m.id,
      name: formatter.format(new Date(2000, m.id - 1, 1)),
    }));
  }

  get selectedMonth() {
    const raw = this.args.month;
    if (raw === null || raw === undefined || raw === "") {
      return null;
    }
    const month = Number(raw);
    return this.availableMonths.some((m) => m.id === month) ? month : null;
  }

  // Available days (depend on the selected year+month, see plugin.rb).
  get availableDays() {
    return this.args.filters?.days || [];
  }

  get selectedDay() {
    const raw = this.args.day;
    if (raw === null || raw === undefined || raw === "") {
      return null;
    }
    const day = Number(raw);
    return this.availableDays.some((d) => d.id === day) ? day : null;
  }

  handleYearChange = (value) => {
    this.args.onChangeYear(value ?? null);
  };

  handleMonthChange = (value) => {
    this.args.onChangeMonth(value ?? null);
  };

  handleDayChange = (value) => {
    this.args.onChangeDay(value ?? null);
  };

  // The "New topic" button is visible only to admins and members of the
  // groups given in the discourse_maps_new_topic_groups setting (list of
  // group ids separated by "|", empty = admins only).
  get canCreateTopic() {
    const user = this.currentUser;
    if (!user) {
      return false;
    }
    if (user.admin) {
      return true;
    }

    const allowedGroupIds = (this.siteSettings.discourse_maps_new_topic_groups || "")
      .split("|")
      .filter(Boolean)
      .map(Number);
    if (!allowedGroupIds.length) {
      return false;
    }

    return (user.groups || []).some((g) => allowedGroupIds.includes(g.id));
  }

  @action
  async createTopic() {
    // We tell the server that the topic originates from the "New topic"
    // button on /map: the "map" tag will be assigned regardless, even if
    // the user doesn't add a location from the composer (see
    // on(:post_created) in plugin.rb). Passing the tag here via `tags:`
    // wouldn't work for non-staff users: the tag group is staff-only, so
    // `composer.filterTags` would silently remove it.
    await this.composer.openNewTopic();
    this.composer.model.set("discourse_maps_from_map", true);
  }

  // Clears all filters, period included: shows all geolocated topics,
  // with no category/tag/country/date filter.
  resetFilters = () => {
    this.args.onChangeCategory(null);
    this.args.onChangeTags([]);
    this.args.onChangeCountry(null);
    this.args.onResetDate();
  };

  // True when the period filter is set to exactly today's date (the
  // default on the very first page load, see routes/map.js): used both
  // for the empty-list message and for the "Today" label of the date
  // filter. Based on the "raw" parameters (this.args.year/month/day,
  // from the query string) and not on this.selectedDay/etc., which
  // instead clear the day if it's not among the available options (no
  // topic that day) — which would then often happen exactly in the
  // "today" case, defeating the comparison.
  // @year/@month/@day arrive as strings from the query string, hence the
  // conversion to Number.
  get isTodayFilter() {
    const { year, month, day } = this.args;
    if (!year || !month || !day) {
      return false;
    }
    const today = new Date();
    return (
      Number(year) === today.getFullYear() &&
      Number(month) === today.getMonth() + 1 &&
      Number(day) === today.getDate()
    );
  }

  // Only topics with a valid location (for the map and the list). The
  // map always shows the entire filtered result, regardless of the
  // pagination of the list below.
  get locatedTopics() {
    return (this.args.topics || []).filter(
      (t) => t.location && t.location.lat && t.location.lng
    );
  }

  // Markers for the map, with an HTML popup (title + category + tags,
  // both clickable). The title has a dedicated class
  // (discourse-maps-popup__title) so it can be styled separately from
  // the rest of the popup's content.
  get markers() {
    return this.locatedTopics.map((topic) => {
      const category = this.category(topic.category_id);

      // The title is already "display: block" via CSS: a <br> after it
      // would only add an extra empty line. It must be joined without a
      // <br>, while category and tags (if both present) stay separated
      // by <br>, one line each.
      const title =
        `<strong class="discourse-maps-popup__title">` +
        `<a href="${topic.url}">${topic.fancy_title || topic.title}</a>` +
        `</strong>`;

      const lines = [];
      const dateRange = formatDateRange(topic.location);
      if (dateRange) {
        lines.push(dateRange);
      }

      if (category) {
        lines.push(
          `${i18n("discourse_maps.popup.category")} ` +
            `<a href="${category.url}">${category.name}</a>`
        );
      }

      if (topic.tags?.length) {
        const tagLinks = topic.tags
          .map((tag) => `<a href="/tag/${tag}">${tag}</a>`)
          .join(", ");
        lines.push(`${i18n("discourse_maps.popup.tags")} ${tagLinks}`);
      }

      return {
        lat: topic.location.lat,
        lng: topic.location.lng,
        popupHtml: title + lines.join("<br>"),
        color: category?.color ? `#${category.color}` : DEFAULT_MARKER_COLOR,
      };
    });
  }

  // Rows for the list below the map: category/tags as links, statistics
  // (views, likes, comments, activity) like in the native topic list.
  get rows() {
    return this.locatedTopics.map((topic) => {
      const category = this.category(topic.category_id);
      const tags = topic.tags || [];

      // "category-<slug>"/"tag-<slug>" classes on the list item, useful
      // for external themes/CSS to customize the look based on category
      // and tags (a tag's slug in Discourse is the tag's name itself).
      const itemClass = [
        category?.slug ? `category-${category.slug}` : null,
        ...tags.map((tag) => `tag-${tag}`),
      ]
        .filter(Boolean)
        .join(" ");

      return {
        topic,
        category,
        itemClass,
        categoryStyle: category
          ? htmlSafe(
              `--category-badge-color: #${category.color};--category-badge-text-color: #${category.text_color};`
            )
          : null,
        tags: tags.map((tag) => ({
          name: tag,
          url: `/tag/${tag}`,
        })),
        commentsCount: Math.max((topic.posts_count || 1) - 1, 0),
        activityDate: this.formatActivityDate(topic),
        dateParts: formatDateParts(topic.location),
      };
    });
  }

  // Activity date shown in the list: prefers the last post, falling back
  // to the topic's creation date. If the received value isn't a valid
  // date we don't show it, instead of risking an "Invalid date". The
  // relative format is computed here (native Intl.RelativeTimeFormat),
  // without depending on other date utilities.
  formatActivityDate(topic) {
    const raw = topic.last_posted_at || topic.created_at;
    if (!raw) {
      return null;
    }

    const date = new Date(raw);
    const time = date.getTime();
    if (Number.isNaN(time)) {
      return null;
    }

    let duration = (time - Date.now()) / 1000;

    for (const division of RELATIVE_TIME_DIVISIONS) {
      if (Math.abs(duration) < division.amount) {
        const formatter = new Intl.RelativeTimeFormat(
          document.documentElement.lang || undefined,
          { numeric: "auto" }
        );
        return formatter.format(Math.round(duration), division.unit);
      }
      duration /= division.amount;
    }

    return null;
  }

  // Subset of rows actually visible (scroll pagination).
  get visibleRows() {
    return this.rows.slice(0, this.visibleCount);
  }

  get hasMore() {
    return this.visibleCount < this.rows.length;
  }

  loadMore = () => {
    if (this.hasMore) {
      this.visibleCount = Math.min(this.visibleCount + PAGE_SIZE, this.rows.length);
    }
  };

  // Observes the sentinel at the bottom of the list: when it enters the
  // viewport, it loads the next group of topics (like infinite scroll).
  setupObserver = (element) => {
    this.observer = new IntersectionObserver((entries) => {
      if (entries[0]?.isIntersecting) {
        this.loadMore();
      }
    });
    this.observer.observe(element);
  };

  teardownObserver = () => {
    this.observer?.disconnect();
    this.observer = null;
  };

  <template>
    <div class="discourse-maps-page" {{didUpdate this.resetPaging @topics}}>
      <h1 class="discourse-maps-page__title">{{i18n "discourse_maps.page_title"}}</h1>

      {{! Actions row visible only on mobile (hidden via CSS on desktop):
          the toggle opens/closes the filters block below, "New post"
          always stays visible (it's not inside the collapsible block)
          at the opposite end of the same row. }}
      <div class="discourse-maps-mobile-actions">
        <DButton
          @action={{this.toggleFilters}}
          @icon={{if this.filtersExpanded "angle-up" "angle-down"}}
          @translatedLabel={{this.filtersToggleLabel}}
          aria-expanded={{if this.filtersExpanded "true" "false"}}
          aria-controls="discourse-maps-filters"
          class="btn-default discourse-maps-filters-toggle"
        />

        {{#if this.canCreateTopic}}
          <DButton
            @icon="far-pen-to-square"
            @label="discourse_maps.filters.new_topic"
            @action={{this.createTopic}}
            class="btn btn-icon-text d-combo-button-button btn-default
              discourse-maps-filters__new-topic discourse-maps-filters__new-topic--mobile"
          />
        {{/if}}
      </div>

      {{! Filters: category and tags, only those present among the listed
          topics. On mobile "is-collapsed" hides them until the toggle is used. }}
      <div
        id="discourse-maps-filters"
        class="discourse-maps-filters {{unless this.filtersExpanded 'is-collapsed'}}"
      >
        <style>{{this.categoryRowIconStyles}}</style>

        <ComboBox
          @value={{this.categoryIdValue}}
          @content={{this.availableCategories}}
          @onChange={{this.handleCategoryChange}}
          @options={{hash none="discourse_maps.filters.all_categories"}}
          class="discourse-maps-filters__category"
        />

        <ComboBox
          @value={{this.selectedTagName}}
          @content={{this.availableTags}}
          @onChange={{this.handleTagChange}}
          @valueProperty="name"
          @options={{hash none="discourse_maps.filters.all_tags"}}
          class="discourse-maps-filters__tags"
        />

        <ComboBox
          @value={{this.selectedCountryName}}
          @content={{this.availableCountries}}
          @onChange={{this.handleCountryChange}}
          @valueProperty="name"
          @options={{hash none="discourse_maps.filters.all_countries"}}
          class="discourse-maps-filters__countries"
        />

        <DiscourseMapsDateFilter
          @year={{this.selectedYear}}
          @month={{this.selectedMonth}}
          @day={{this.selectedDay}}
          @isToday={{this.isTodayFilter}}
          @availableYears={{this.availableYears}}
          @availableMonths={{this.availableMonths}}
          @availableDays={{this.availableDays}}
          @onSelectYear={{this.handleYearChange}}
          @onSelectMonth={{this.handleMonthChange}}
          @onSelectDay={{this.handleDayChange}}
          class="discourse-maps-filters__date"
        />

        <button
          type="button"
          class="btn btn-icon-text d-page-action-button btn-small btn-danger discourse-maps-filters__reset
            {{unless this.hasActiveFilters 'disabled'}}"
          disabled={{if this.hasActiveFilters false true}}
          {{on "click" this.resetFilters}}
        >
          {{i18n "discourse_maps.filters.reset"}}
        </button>

        {{#if this.canCreateTopic}}
          <DButton
            @icon="far-pen-to-square"
            @label="discourse_maps.filters.new_topic"
            @action={{this.createTopic}}
            class="btn btn-icon-text d-combo-button-button btn-default discourse-maps-filters__new-topic"
          />
        {{/if}}
      </div>

      {{! Map with all the pins of the filtered result. }}
      <DiscourseMapsMap @markers={{this.markers}} @interactive={{true}} />

      {{! List of geolocated topics (ordered by date, scroll-paginated). }}
      <div class="discourse-maps-list">
        {{#each this.visibleRows as |row|}}
          <div class="discourse-maps-list__item {{row.itemClass}} {{if row.topic.visited 'visited'}}">
            <div class="discourse-maps-list__thumbnail">
              <a href={{row.topic.url}} role="img" aria-label={{row.topic.title}}>
                {{#if row.topic.image_url}}
                  <img src={{row.topic.image_url}} loading="lazy" alt="" />
                {{else}}
                  <div class="thumbnail-placeholder">
                    {{icon "comments"}}
                  </div>
                {{/if}}
              </a>
            </div>

            <div class="discourse-maps-list__content" style="display: flex; flex-direction: column; align-items: flex-start;">
              <a href={{row.topic.url}} class="discourse-maps-list__title">
                {{row.topic.title}}
              </a>

              {{#if row.dateParts}}
                <div class="discourse-maps-list__date" style="order: -1;">
                  <span class="discourse-maps-list__date-value">{{row.dateParts.start}}</span>
                  {{#unless row.dateParts.sameDay}}
                    <span class="discourse-maps-list__date-separator" aria-hidden="true">–</span>
                    <span class="discourse-maps-list__date-value">{{row.dateParts.end}}</span>
                  {{/unless}}
                </div>
              {{/if}}

              <div class="discourse-maps-list__meta">
                {{#if row.category}}
                  <a
                    class="badge-category__wrapper"
                    style={{row.categoryStyle}}
                    href={{row.category.url}}
                  >
                    <span class="badge-category --style-square">
                      <span class="badge-category__name">{{row.category.name}}</span>
                    </span>
                  </a>
                {{/if}}

                {{#if row.tags.length}}
                  <ul class="discourse-tags" aria-label="Tags">
                    {{#each row.tags as |tag|}}
                      <li><a href={{tag.url}} class="discourse-tag simple">{{tag.name}}</a></li>
                    {{/each}}
                  </ul>
                {{/if}}
              </div>
            </div>

            <div class="discourse-maps-list__stats">
              <span class="discourse-maps-list__stat">
                {{icon "eye"}}<span class="number">{{row.topic.views}}</span>
              </span>
              <span class="discourse-maps-list__stat">
                {{icon "heart"}}<span class="number">{{row.topic.like_count}}</span>
              </span>
              <span class="discourse-maps-list__stat">
                {{icon "comment"}}<span class="number">{{row.commentsCount}}</span>
              </span>
              {{#if row.activityDate}}
                <span class="discourse-maps-list__relative-date">{{row.activityDate}}</span>
              {{/if}}
            </div>
          </div>
        {{else}}
          <p class="discourse-maps-list__empty">
            {{#if this.isTodayFilter}}
              {{i18n "discourse_maps.list.empty_today"}}
            {{else}}
              {{i18n "discourse_maps.list.empty"}}
            {{/if}}
          </p>
        {{/each}}

        {{#if this.hasMore}}
          <div
            class="discourse-maps-list__sentinel"
            {{didInsert this.setupObserver}}
            {{willDestroy this.teardownObserver}}
          ></div>
        {{/if}}
      </div>
    </div>
  </template>
}
