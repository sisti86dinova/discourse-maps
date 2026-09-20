// ============================================================================
//  Discourse Maps - Reusable map component.
//
//  Renders an interactive map in a <div> container. It's deliberately
//  generic: it accepts one or more markers, so it can be used both on
//  the topic page (a single pin) and on the /map page (many pins).
//
//  Arguments:
//    @location    - single point { lat, lng, display_name } (optional)
//    @markers     - array of points (optional, takes priority over @location)
//    @interactive - enables zoom/pan (default: true)
// ============================================================================

import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { createMap } from "../lib/discourse-maps-provider";

export default class DiscourseMapsMap extends Component {
  @service siteSettings;

  // References to the container and the created map.
  element = null;
  mapHandle = null;

  // Markers to show: prefers @markers, otherwise uses the single @location.
  get markers() {
    if (this.args.markers) {
      return this.args.markers;
    }
    return this.args.location ? [this.args.location] : [];
  }

  // Picks the correct API key based on the configured provider.
  get apiKey() {
    return this.siteSettings.discourse_maps_provider === "google"
      ? this.siteSettings.discourse_maps_google_api_key
      : this.siteSettings.discourse_maps_locationiq_api_key;
  }

  // Builds (or rebuilds) the map in the stored container.
  async build() {
    this.mapHandle = await createMap(this.element, {
      provider: this.siteSettings.discourse_maps_provider,
      apiKey: this.apiKey,
      // Site language: used to load the Google Maps library (labels and
      // geocoder consistent with the forum's language).
      language: (this.siteSettings.default_locale || "en").replace("_", "-"),
      markers: this.markers,
      interactive: this.args.interactive ?? true,
      // The "color" site setting stores the hex value without "#" (like
      // category colors): we normalize it here to use it directly in the SVG.
      clusterColor: this.siteSettings.discourse_maps_cluster_color
        ? `#${this.siteSettings.discourse_maps_cluster_color.replace(/^#/, "")}`
        : undefined,
    });
  }

  @action
  async setup(element) {
    this.element = element;
    await this.build();
  }

  // Rebuilds the map when the markers (or the location) change, e.g. when
  // the filters on the /map page change.
  @action
  async refresh() {
    this.mapHandle?.destroy?.();
    await this.build();
  }

  @action
  teardown() {
    this.mapHandle?.destroy?.();
    this.mapHandle = null;
  }

  <template>
    <div
      class="discourse-map"
      {{didInsert this.setup}}
      {{didUpdate this.refresh this.args.markers this.args.location}}
      {{willDestroy this.teardown}}
    ></div>
  </template>
}

