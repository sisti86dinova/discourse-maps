// ============================================================================
//  Discourse Maps - Location entry modal (composer).
//
//  Opened by the button in the composer toolbar. The user types the full
//  address in a single free-text field: it's the geocoding provider
//  (LocationIQ or Google) that interprets it, returning coordinates,
//  formatted address and country. We save the result on the composer's
//  model, so it can be sent to the server on topic creation.
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { i18n } from "discourse-i18n";
import { geocodeAddress } from "../lib/discourse-maps-provider";

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

  constructor() {
    super(...arguments);

    // Retrieves a location already saved on the composer, if any, for editing.
    const existing = this.composer?.model?.discourse_maps_location;
    if (existing) {
      this.address = existing.address ?? existing.display_name ?? "";
      this.startDate = existing.start_date ?? "";
      this.endDate = existing.end_date ?? "";
    }
  }

  // Translated error message (if any).
  get errorMessage() {
    return this.errorKey ? i18n(`discourse_maps.modal.errors.${this.errorKey}`) : null;
  }

  @action
  updateAddress(event) {
    this.address = event.target.value;
  }

  @action
  updateStartDate(event) {
    this.startDate = event.target.value;
  }

  @action
  updateEndDate(event) {
    this.endDate = event.target.value;
  }

  // Performs the geocoding and saves the location on the composer's model.
  @action
  async save() {
    this.errorKey = null;

    // The dates are as required as the address: without them, the topic
    // could never show up in the /map page's date filters.
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
      const result = await geocodeAddress(this.address, this.siteSettings);

      // We save the typed address + the geocoding result (coordinates,
      // formatted address, country) + the reference period on the
      // composer's model.
      this.composer.model.set("discourse_maps_location", {
        address: this.address,
        lat: result.lat,
        lng: result.lng,
        display_name: result.display_name,
        country: result.country,
        start_date: this.startDate,
        end_date: this.endDate,
      });

      this.args.closeModal();
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

  // Removes the location associated with the topic, if any.
  @action
  remove() {
    this.composer.model.set("discourse_maps_location", null);
    this.args.closeModal();
  }

  <template>
    <DModal
      @title={{i18n "discourse_maps.modal.title"}}
      @closeModal={{@closeModal}}
      class="discourse-maps-modal"
    >
      <:body>
        <form class="discourse-maps-form">
          <div class="control-group">
            <label>{{i18n "discourse_maps.modal.fields.address"}}</label>
            <input
              type="text"
              placeholder={{i18n "discourse_maps.modal.fields.address_placeholder"}}
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
        </form>
      </:body>

      <:footer>
        <DButton
          @action={{this.save}}
          @label="discourse_maps.modal.save"
          @isLoading={{this.loading}}
          class="btn-primary"
        />
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
