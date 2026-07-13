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

  // I filtri sono legati alla querystring, quindi per loro natura
  // "sticky": senza questo hook, uscendo da /map e rientrandoci con un link
  // semplice (senza parametri, es. dalla sidebar) il controller manterrebbe
  // ancora i valori della visita precedente. Ember chiama resetController
  // quando si esce dalla rotta (isExiting): qui azzeriamo i filtri così la
  // pagina riparte sempre pulita, a meno che l'URL di destinazione non porti
  // esplicitamente dei parametri (link condiviso, bookmark, ecc.).
  resetController(controller, isExiting) {
    if (isExiting) {
      controller.set("category_id", null);
      controller.set("tags", null);
      controller.set("countries", null);
    }
  }

  // Titolo della pagina (tab del browser / breadcrumb).
  titleToken() {
    return i18n("discourse_maps.page_title");
  }
}

