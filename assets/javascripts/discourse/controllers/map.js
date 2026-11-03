// ============================================================================
//  Discourse Maps - /map page controller.
//
//  Manages the filter state (category, tags and country) as query params,
//  so they're shareable via URL and persist across page refresh.
// ============================================================================

import Controller from "@ember/controller";
import { action, computed } from "@ember/object";

export default class MapController extends Controller {
  // Query params synced with the URL.
  queryParams = [
    "category_id",
    "tags",
    "countries",
    "year",
    "month",
    "day",
    "upcoming",
  ];

  category_id = null;
  // Selected tags are stored as a CSV string (e.g. "events,news").
  tags = null;
  // Selected countries are stored as a CSV string of ISO 3166-1 alpha-2
  // codes (e.g. "IT"): the name shown in the filter is derived from the
  // code, so the URL doesn't depend on the site's language.
  countries = null;
  // Period filter: year, month (1-12) and day, hierarchical (month only
  // makes sense with a year selected, day only with year+month). On the
  // very first page load the route applies the default from the
  // discourse_maps_default_date_filter site setting (see routes/map.js),
  // to avoid showing all geolocated topics at once: either today's exact
  // date (year/month/day) or, with no upper bound, "upcoming".
  year = null;
  month = null;
  day = null;
  // Mutually exclusive with year/month/day: true shows every topic whose
  // period hasn't ended yet (today onward), with no specific date chosen.
  // Picking an explicit year (including "any year") always clears it,
  // same as how it clears month/day (see updateYear below).
  upcoming = null;

  // Array of selected tags (convenient for the tag chooser).
  //
  // @computed with an explicit dependency on "tags": a native getter
  // (without @computed) on a classic Controller does NOT re-run when
  // this.tags changes via this.set(), because it reads the property with
  // a plain this.tags instead of an Ember-tracked access. The result
  // would therefore stay stuck at the value computed on the first
  // render, even though the URL and the model update correctly.
  @computed("tags")
  get selectedTags() {
    return this.tags ? this.tags.split(",") : [];
  }

  // Currently selected country (single filter, like the category). Same
  // reason as above for the explicit @computed("countries").
  @computed("countries")
  get countryCode() {
    return this.countries ? this.countries.split(",")[0] : null;
  }

  // Updates the category filter.
  @action
  updateCategory(categoryId) {
    this.set("category_id", categoryId || null);
  }

  // Updates the tag filter (receives an array, we store it as CSV).
  @action
  updateTags(tags) {
    this.set("tags", tags?.length ? tags.join(",") : null);
  }

  // Updates the country filter.
  @action
  updateCountry(countryCode) {
    this.set("countries", countryCode || null);
  }

  // Updates the year filter. Changing the year potentially invalidates
  // the already-selected month and day (they might not exist as options
  // for the new year): we always clear them, the user reselects them if
  // needed. Also clears "upcoming" (including when year is cleared to
  // null, i.e. the picker's "Any year"): interacting with the year
  // picker at all means the user is now manually managing the period,
  // so the page's default floor no longer applies.
  @action
  updateYear(year) {
    this.set("year", year || null);
    this.set("month", null);
    this.set("day", null);
    this.set("upcoming", null);
  }

  // Updates the month filter. Same reasoning as updateYear for the day.
  @action
  updateMonth(month) {
    this.set("month", month || null);
    this.set("day", null);
  }

  // Updates the day filter.
  @action
  updateDay(day) {
    this.set("day", day || null);
  }

  // Clears the period filter (used by the "Remove filters" button): no
  // year/month/day/upcoming selected, so all geolocated topics with no
  // date filter, consistent with category/tag/country being cleared the
  // same way by the same button.
  @action
  resetDateFilter() {
    this.set("year", null);
    this.set("month", null);
    this.set("day", null);
    this.set("upcoming", null);
  }
}
