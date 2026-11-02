// ============================================================================
//  Discourse Maps - Location entry modal (composer).
//
//  Opened by the button in the composer toolbar. The user types the full
//  address in a single free-text field: it's the geocoding provider
//  (LocationIQ or Google) that interprets it, returning coordinates,
//  formatted address and country. We save the result on the composer's
//  model, so it can be sent to the server on topic creation.
//
//  The geocoded point is shown as a map preview (with the matched
//  address below it) before it's actually saved: the provider sometimes
//  mismatches an address to a same-named place elsewhere in the world
//  (e.g. a village called "Parigi" in India instead of Paris, France),
//  and without a visual check that only surfaces once the topic is
//  already on the map, pin in the wrong place.
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import { geocodeAddress } from "../lib/discourse-maps-provider.js";
import DiscourseMapsStaticMap from "./discourse-maps-static-map.gjs";

export default class DiscourseMapsLocationModal extends Component {
  @service composer;
  @service siteSettings;

  // Full address typed by the user (pre-filled if the topic already has
  // a location).
  @tracked address = "";

  // Start/end date of the geolocated event ("YYYY-MM-DD" format, the same
  // format returned by <input type="date">). Required: every post with a
  // location must also have a reference period.
  @tracked startDate = "";
  @tracked endDate = "";

  // State of the geocoding operation.
  @tracked loading = false;
  @tracked errorKey = null;

  // Result of the last successful geocoding ({ lat, lng, display_name,
  // country_code, country }), shown as a map preview the user must
  // confirm before it's actually saved. Cleared whenever the address
  // text changes, since it would no longer match what's previewed.
  @tracked geocodeResult = null;

  constructor() {
    super(...arguments);

    // Prefills from the location already on the composer model, if this
    // session already touched it (set or removed: an explicit null means
    // the user just removed it, and must NOT fall back to the topic's
    // saved value below). Otherwise, when editing the first post of an
    // already geolocated topic, falls back to the one saved on the topic.
    const modelLocation = this.composer?.model?.discourse_maps_location;
    const existing =
      modelLocation !== undefined
        ? modelLocation
        : this.composer?.model?.topic?.discourse_maps_location;

    if (existing) {
      this.address = existing.address ?? existing.display_name ?? "";
      this.startDate = existing.start_date ?? "";
      this.endDate = existing.end_date ?? "";

      // The coordinates are already known (no geocoding call needed):
      // shows the preview right away, for a visual check of a location
      // set earlier, without requiring the address to be re-verified.
      if (existing.lat != null && existing.lng != null) {
        this.geocodeResult = existing;
      }
    }
  }

  // Translated error message (if any).
  get errorMessage() {
    return this.errorKey ? i18n(`discourse_maps.modal.errors.${this.errorKey}`) : null;
  }

  @action
  updateAddress(event) {
    this.address = event.target.value;
    // The previous preview no longer matches the edited address: the
    // user must verify it again before being able to confirm.
    this.geocodeResult = null;
  }

  @action
  updateStartDate(event) {
    this.startDate = event.target.value;
  }

  @action
  updateEndDate(event) {
    this.endDate = event.target.value;
  }

  // Geocodes the typed address and shows the result as a map preview
  // (see @geocodeResult), instead of saving it right away: the provider
  // can mismatch an address to a same-named place elsewhere in the
  // world, and this is the only point where that's still cheap to catch.
  @action
  async preview() {
    this.errorKey = null;

    // The dates are as required as the address: without them, the topic
    // could never show up in the /map page's date filters. Checked here
    // rather than only in confirm(), so the user isn't led to verify the
    // address just to be stopped by a missing date right after.
    if (!this.startDate || !this.endDate) {
      this.errorKey = "missing_dates";
      return;
    }

    if (this.endDate < this.startDate) {
      this.errorKey = "end_before_start";
      return;
    }

    this.loading = true;

    try {
      this.geocodeResult = await geocodeAddress(this.address, this.siteSettings);
    } catch (error) {
      // "not_found"/"empty_address" have dedicated messages, everything else is generic.
      this.errorKey =
        error?.message === "not_found" || error?.message === "empty_address"
          ? error.message
          : "generic";
    } finally {
      this.loading = false;
    }
  }

  // Discards the previewed result to let the user adjust the address,
  // without losing the dates already entered.
  @action
  editAddress() {
    this.geocodeResult = null;
    this.errorKey = null;
  }

  // Saves the previewed location (confirmed by the user) on the
  // composer's model.
  @action
  confirm() {
    // We save the typed address + the geocoding result (coordinates,
    // formatted address, country) + the reference period on the
    // composer's model. country_code is what identifies the country in
    // the /map filter; country is only the name at save time, kept as a
    // fallback for codes the browser can't resolve.
    this.composer.model.set("discourse_maps_location", {
      address: this.address,
      lat: this.geocodeResult.lat,
      lng: this.geocodeResult.lng,
      display_name: this.geocodeResult.display_name,
      country_code: this.geocodeResult.country_code,
      country: this.geocodeResult.country,
      start_date: this.startDate,
      end_date: this.endDate,
    });

    this.args.closeModal();
  }

  // Removes the location associated with the topic, if any.
  @action
  remove() {
    this.composer.model.set("discourse_maps_location", null);
    this.args.closeModal();
  }

  <template>
    <DModal
      class="discourse-maps-modal"
      @closeModal={{@closeModal}}
      @title={{i18n "discourse_maps.modal.title"}}
    >
      <:body>
        <form class="discourse-maps-form">
          <div class="control-group">
            <label>{{i18n "discourse_maps.modal.fields.address"}}</label>
            <input
              placeholder={{i18n "discourse_maps.modal.fields.address_placeholder"}}
              type="text"
              value={{this.address}}
              {{on "input" this.updateAddress}}
            />
          </div>

          <div class="control-group discourse-maps-form__dates">
            <div>
              <label>{{i18n "discourse_maps.modal.fields.start_date"}}</label>
              <input
                type="date"
                value={{this.startDate}}
                {{on "input" this.updateStartDate}}
              />
            </div>

            <div>
              <label>{{i18n "discourse_maps.modal.fields.end_date"}}</label>
              <input
                type="date"
                value={{this.endDate}}
                {{on "input" this.updateEndDate}}
              />
            </div>
          </div>

          {{#if this.errorMessage}}
            <div class="discourse-maps-form__error alert alert-error">
              {{this.errorMessage}}
            </div>
          {{/if}}

          {{#if this.geocodeResult}}
            <div class="control-group discourse-maps-form__preview">
              <label>{{i18n "discourse_maps.modal.preview_label"}}</label>
              <DiscourseMapsStaticMap @location={{this.geocodeResult}} />
              <p class="discourse-maps-form__preview-address">
                {{this.geocodeResult.display_name}}
              </p>
            </div>
          {{/if}}
        </form>
      </:body>

      <:footer>
        {{#if this.geocodeResult}}
          <DButton
            class="btn-primary"
            @action={{this.confirm}}
            @label="discourse_maps.modal.save"
          />
          <DButton
            @action={{this.editAddress}}
            @label="discourse_maps.modal.edit_address"
          />
        {{else}}
          <DButton
            class="btn-primary"
            @action={{this.preview}}
            @isLoading={{this.loading}}
            @label="discourse_maps.modal.preview"
          />
        {{/if}}
        <DButton
          @action={{this.remove}}
          @label="discourse_maps.modal.remove"
        />
        <DButton
          @action={{@closeModal}}
          @label="discourse_maps.modal.cancel"
        />
      </:footer>
    </DModal>
  </template>
}
