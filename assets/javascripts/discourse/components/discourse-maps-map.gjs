// ============================================================================
//  Discourse Maps - Componente mappa riutilizzabile.
//
//  Renderizza una mappa interattiva in un contenitore <div>. È volutamente
//  generico: accetta uno o più marker, così potrà essere usato sia nella
//  pagina del topic (un solo pin) sia nella pagina /map (molti pin).
//
//  Argomenti:
//    @location    - singolo punto { lat, lng, display_name } (opzionale)
//    @markers     - array di punti (opzionale, ha priorità su @location)
//    @interactive - abilita zoom/spostamento (default: true)
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

  // Riferimenti al contenitore e alla mappa creata.
  element = null;
  mapHandle = null;

  // Marker da mostrare: preferisce @markers, altrimenti usa @location singolo.
  get markers() {
    if (this.args.markers) {
      return this.args.markers;
    }
    return this.args.location ? [this.args.location] : [];
  }

  // Sceglie la chiave API corretta in base al provider configurato.
  get apiKey() {
    return this.siteSettings.discourse_maps_provider === "google"
      ? this.siteSettings.discourse_maps_google_api_key
      : this.siteSettings.discourse_maps_locationiq_api_key;
  }

  // Costruisce (o ricostruisce) la mappa nel contenitore memorizzato.
  async build() {
    this.mapHandle = await createMap(this.element, {
      provider: this.siteSettings.discourse_maps_provider,
      apiKey: this.apiKey,
      markers: this.markers,
      interactive: this.args.interactive ?? true,
    });
  }

  @action
  async setup(element) {
    this.element = element;
    await this.build();
  }

  // Ricostruisce la mappa quando i marker (o la posizione) cambiano, ad es.
  // al variare dei filtri nella pagina /map.
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

