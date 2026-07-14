// ============================================================================
//  Discourse Maps - Initializer principale lato client.
//
//  Responsabilità in questo step:
//    - aggiungere un pulsante nella toolbar del composer che apre il modal
//      per inserire la posizione geografica;
//    - registrare la serializzazione del dato "discourse_maps_location" così
//      che venga inviato al server alla creazione del topic e sia disponibile
//      sul modello del topic appena creato.
// ============================================================================

import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import DiscourseMapsLocationModal from "../components/discourse-maps-location-modal";

export default {
  name: "discourse-maps",

  initialize() {
    withPluginApi("1.8.0", (api) => {
      const siteSettings = api.container.lookup("service:site-settings");

      // Se il plugin è disabilitato non aggiungiamo nulla.
      if (!siteSettings.discourse_maps_enabled) {
        return;
      }

      // --- Nasconde il tag "mappa" nelle tendine di selezione tag ----------
      // Protezione visiva in più, oltre al tag group in sola lettura lato
      // server (che impedisce di assegnarlo dal composer): nasconde la voce
      // anche se dovesse comparire in un widget di selezione tag non
      // coperto da quel permesso.
      const mapTagId = siteSettings.discourse_maps_map_tag_id;
      if (mapTagId) {
        const style = document.createElement("style");
        style.textContent = `.tags-input li[data-value="${mapTagId}"] { display: none !important; }`;
        document.head.appendChild(style);
      }

      // --- Link alla pagina /map nella sidebar -----------------------------
      api.addCommunitySectionLink({
        name: "discourse-maps",
        route: "map",
        title: i18n("discourse_maps.page_title"),
        text: i18n("discourse_maps.page_title"),
        icon: "globe",
      });

      // --- Serializzazione dei dati geografici -----------------------------
      // Invia "discourse_maps_location" al server alla creazione del topic...
      api.serializeOnCreate("discourse_maps_location");
      // ...e lo copia sul modello del topic appena creato (per il rendering).
      api.serializeToTopic(
        "discourse_maps_location",
        "topic.discourse_maps_location"
      );

      // --- Pulsante nella toolbar del composer -----------------------------
      api.onToolbarCreate((toolbar) => {
        toolbar.addButton({
          id: "discourse-maps-location",
          group: "extras",
          icon: "location-dot",
          title: "discourse_maps.composer.button_title",
          action: () => {
            const modal = api.container.lookup("service:modal");
            modal.show(DiscourseMapsLocationModal);
          },
        });
      });
    });
  },
};


