// ============================================================================
//  Discourse Maps - Rotta client /map.
//
//  Carica dal server (endpoint /map.json) l'elenco dei topic con tag mappa e
//  relativa posizione, che verranno mostrati sulla mappa e nella lista.
// ============================================================================

import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class MapRoute extends DiscourseRoute {
  model() {
    return ajax("/map.json");
  }

  // Titolo della pagina (tab del browser / breadcrumb).
  titleToken() {
    return i18n("discourse_maps.page_title");
  }
}

