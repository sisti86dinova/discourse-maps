// ============================================================================
//  Discourse Maps - Initializer principale lato client.
//
//  In questo primo step l'initializer è uno scheletro: viene registrato ma
//  non aggiunge ancora comportamenti. Negli step successivi qui collegheremo:
//    - il pulsante/pannello nel composer per inserire i dati geografici;
//    - la logica della pagina /map e della mappa interattiva;
//    - i filtri per categorie e tag.
// ============================================================================

import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "discourse-maps",

  initialize() {
    withPluginApi("1.8.0", () => {
      // Segnaposto: nessuna personalizzazione attiva in questo step.
      // Le funzionalità verranno aggiunte progressivamente.
    });
  },
};

