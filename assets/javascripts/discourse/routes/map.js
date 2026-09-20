// ============================================================================
//  Discourse Maps - /map client route.
//
//  Loads from the server (/map.json endpoint) the list of topics with the
//  map tag and their location, to be shown on the map and in the list.
// ============================================================================

import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class MapRoute extends DiscourseRoute {
  @service router;

  // Filters are query params: when they change, we reload the data from the server.
  queryParams = {
    category_id: { refreshModel: true },
    tags: { refreshModel: true },
    countries: { refreshModel: true },
    year: { refreshModel: true },
    month: { refreshModel: true },
    day: { refreshModel: true },
  };

  // Becomes true after the first entry into the route in this visit: reset
  // by resetController when leaving, so the default kicks in again on the
  // next visit but isn't reapplied if the user manually removes the date
  // filter (the "Remove filters" button) while staying on the page.
  dateDefaultApplied = false;

  model(params, transition) {
    // First entry into the page in this visit, with no explicit date
    // filter in the URL: we default-filter on today's date, to avoid
    // showing all geolocated topics at once (potentially thousands). The
    // redirect (with the resulting new call to model(), this time with
    // dateDefaultApplied already true) entirely replaces this first
    // pass's ajax request.
    if (!this.dateDefaultApplied) {
      this.dateDefaultApplied = true;

      if (!params.year && !params.month && !params.day) {
        const today = new Date();
        // The redirect targets the same route, only changing the query
        // params: without explicitly aborting the ongoing transition, the
        // router throws an internal TypeError ("Cannot read properties of
        // undefined (reading 'name')") because the transition to the
        // current route hasn't been finalized yet when we try to replace
        // it (known Ember bug, see emberjs/ember.js#18577).
        transition.abort();
        this.router.replaceWith("map", {
          queryParams: {
            year: today.getFullYear(),
            month: today.getMonth() + 1,
            day: today.getDate(),
          },
        });
        return;
      }
    }

    // We only send the server the filters that are actually set.
    const data = {};
    if (params.category_id) {
      data.category_id = params.category_id;
    }
    if (params.tags) {
      data.tags = params.tags;
    }
    if (params.countries) {
      data.countries = params.countries;
    }
    if (params.year) {
      data.year = params.year;
    }
    if (params.month) {
      data.month = params.month;
    }
    if (params.day) {
      data.day = params.day;
    }

    return ajax("/map.json", { data });
  }

  // Filters are tied to the query string, so by nature they're "sticky":
  // without this hook, leaving /map and coming back with a plain link (no
  // parameters, e.g. from the sidebar) the controller would still keep
  // the previous visit's values. Ember calls resetController when leaving
  // the route (isExiting): here we clear the filters so the page always
  // starts fresh, unless the destination URL explicitly carries
  // parameters (shared link, bookmark, etc.).
  resetController(controller, isExiting) {
    if (isExiting) {
      controller.set("category_id", null);
      controller.set("tags", null);
      controller.set("countries", null);
      controller.set("year", null);
      controller.set("month", null);
      controller.set("day", null);
      this.dateDefaultApplied = false;
    }
  }

  // Page title (browser tab / breadcrumb).
  titleToken() {
    return i18n("discourse_maps.page_title");
  }
}
