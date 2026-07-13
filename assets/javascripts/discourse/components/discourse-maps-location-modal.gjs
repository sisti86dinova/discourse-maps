// ============================================================================
//  Discourse Maps - Modal di inserimento posizione (composer).
//
//  Viene aperto dal pulsante nella toolbar del composer. L'utente digita
//  l'indirizzo completo in un solo campo di testo libero: è il provider di
//  geocoding (LocationIQ o Google) a interpretarlo, restituendo coordinate,
//  indirizzo formattato e paese. Salviamo il risultato sul modello del
//  composer, così da poterlo inviare al server alla creazione del topic.
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

  // Indirizzo completo digitato dall'utente (pre-compilato se il topic ha
  // già una posizione).
  @tracked address = "";

  // Stato dell'operazione di geocoding.
  @tracked loading = false;
  @tracked errorKey = null;

  constructor() {
    super(...arguments);

    // Recupera un'eventuale posizione già salvata sul composer per l'editing.
    const existing = this.composer?.model?.discourse_maps_location;
    if (existing) {
      this.address = existing.address ?? existing.display_name ?? "";
    }
  }

  // Messaggio di errore tradotto (se presente).
  get errorMessage() {
    return this.errorKey ? i18n(`discourse_maps.modal.errors.${this.errorKey}`) : null;
  }

  @action
  updateAddress(event) {
    this.address = event.target.value;
  }

  // Esegue il geocoding e salva la posizione sul modello del composer.
  @action
  async save() {
    this.errorKey = null;
    this.loading = true;

    try {
      const result = await geocodeAddress(this.address, this.siteSettings);

      // Salviamo l'indirizzo digitato + il risultato del geocoding
      // (coordinate, indirizzo formattato, paese) sul modello del composer.
      this.composer.model.set("discourse_maps_location", {
        address: this.address,
        lat: result.lat,
        lng: result.lng,
        display_name: result.display_name,
        country: result.country,
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
            <label>{{i18n "discourse_maps.modal.fields.address"}}</label>
            <input
              type="text"
              placeholder={{i18n "discourse_maps.modal.fields.address_placeholder"}}
              value={{this.address}}
              {{on "input" this.updateAddress}}
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
