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
  // I filtri sono query param: quando cambiano, ricarichiamo i dati dal server.
  queryParams = {
    category_id: { refreshModel: true },
    tags: { refreshModel: true },
    countries: { refreshModel: true },
  };

  model(params) {
    // Inviamo al server solo i filtri effettivamente valorizzati.
    const data = {};
    if (params.category_id) {
      data.category_id = params.category_id;
    }
    if (params.tags) {
      data.tags = params.tags;
    }
    if (params.countries) {
      data.countries = params.countries;
    }

    return ajax("/map.json", { data });
  }

  // Titolo della pagina (tab del browser / breadcrumb).
  titleToken() {
    return i18n("discourse_maps.page_title");
  }
}

