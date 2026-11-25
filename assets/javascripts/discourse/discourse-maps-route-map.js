// ============================================================================
//  Discourse Maps - Registration of the map page's client route.
//
//  Adds the "map" route to the Ember application router, at MAP_PATH.
// ============================================================================

import { MAP_PATH } from "./lib/discourse-maps-paths.js";

export default function () {
  this.route("map", { path: MAP_PATH });
}

