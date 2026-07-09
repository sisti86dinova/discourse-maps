// ============================================================================
//  Discourse Maps - Modal di inserimento posizione (composer).
//
//  Viene aperto dal pulsante nella toolbar del composer. Raccoglie i campi
//  dell'indirizzo, esegue il geocoding con il provider configurato e salva il
//  risultato (indirizzo + coordinate) sul modello del composer, così da poterlo
//  inviare al server alla creazione del topic.
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { i18n } from "discourse-i18n";
import { geocodeAddress } from "../lib/discourse-maps-provider";

export default class DiscourseMapsLocationModal extends Component {
  @service composer;
  @service siteSettings;

  // Campi dell'indirizzo (pre-compilati se il topic ha già una posizione).
  @tracked street = "";
  @tracked house_number = "";
  @tracked postcode = "";
  @tracked city = "";
  @tracked country = "";

  // Stato dell'operazione di geocoding.
  @tracked loading = false;
  @tracked errorKey = null;

  constructor() {
    super(...arguments);

    // Recupera un'eventuale posizione già salvata sul composer per l'editing.
    const existing = this.composer?.model?.discourse_maps_location;
    if (existing) {
      this.street = existing.street ?? "";
      this.house_number = existing.house_number ?? "";
      this.postcode = existing.postcode ?? "";
      this.city = existing.city ?? "";
      this.country = existing.country ?? "";
    }
  }

  // Messaggio di errore tradotto (se presente).
  get errorMessage() {
    return this.errorKey ? i18n(`discourse_maps.modal.errors.${this.errorKey}`) : null;
  }

  // Aggiorna in modo generico un campo dell'indirizzo.
  @action
  updateField(field, event) {
    this[field] = event.target.value;
  }

  // Esegue il geocoding e salva la posizione sul modello del composer.
  @action
  async save() {
    this.errorKey = null;
    this.loading = true;

    const address = {
      street: this.street,
      house_number: this.house_number,
      postcode: this.postcode,
      city: this.city,
      country: this.country,
    };

    try {
      const result = await geocodeAddress(address, this.siteSettings);

      // Salviamo indirizzo + coordinate sul modello del composer.
      this.composer.model.set("discourse_maps_location", {
        ...address,
        lat: result.lat,
        lng: result.lng,
        display_name: result.display_name,
      });

      this.args.closeModal();
    } catch (error) {
      // "not_found"/"empty_address" hanno messaggi dedicati, il resto è generico.
      this.errorKey =
        error?.message === "not_found" || error?.message === "empty_address"
          ? error.message
          : "generic";
    } finally {
      this.loading = false;
    }
  }

  // Rimuove la posizione eventualmente associata al topic.
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
            <label>{{i18n "discourse_maps.modal.fields.street"}}</label>
            <input
              type="text"
              value={{this.street}}
              {{on "input" (fn this.updateField "street")}}
            />
          </div>

          <div class="control-group">
            <label>{{i18n "discourse_maps.modal.fields.house_number"}}</label>
            <input
              type="text"
              value={{this.house_number}}
              {{on "input" (fn this.updateField "house_number")}}
            />
          </div>

          <div class="control-group">
            <label>{{i18n "discourse_maps.modal.fields.postcode"}}</label>
            <input
              type="text"
              value={{this.postcode}}
              {{on "input" (fn this.updateField "postcode")}}
            />
          </div>

          <div class="control-group">
            <label>{{i18n "discourse_maps.modal.fields.city"}}</label>
            <input
              type="text"
              value={{this.city}}
              {{on "input" (fn this.updateField "city")}}
            />
          </div>

          <div class="control-group">
            <label>{{i18n "discourse_maps.modal.fields.country"}}</label>
            <input
              type="text"
              value={{this.country}}
              {{on "input" (fn this.updateField "country")}}
            />
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

