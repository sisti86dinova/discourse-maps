// ============================================================================
//  Discourse Maps - Rotta client /map.
//
//  Carica dal server (endpoint /map.json) l'elenco dei topic con tag mappa e
//  relativa posizione, che verranno mostrati sulla mappa e nella lista.
// ============================================================================

import { service } from "@ember/service";
import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class MapRoute extends DiscourseRoute {
  @service router;

  // I filtri sono query param: quando cambiano, ricarichiamo i dati dal server.
  queryParams = {
    category_id: { refreshModel: true },
    tags: { refreshModel: true },
    countries: { refreshModel: true },
    year: { refreshModel: true },
    month: { refreshModel: true },
    day: { refreshModel: true },
  };

  // Diventa true dopo il primo ingresso nella rotta in questa visita:
  // azzerato da resetController quando si esce, così il default scatta di
  // nuovo alla prossima visita ma non viene riapplicato se l'utente rimuove
  // manualmente il filtro data (pulsante "Rimuovi filtri") restando sulla
  // pagina.
  dateDefaultApplied = false;

  model(params, transition) {
    // Primo ingresso nella pagina in questa visita, senza alcun filtro data
    // esplicito in URL: filtriamo di default sulla data odierna, per evitare
    // di mostrare in una volta sola tutti i topic geolocalizzati
    // (potenzialmente migliaia). Il redirect (con conseguente nuova chiamata
    // a model(), stavolta con dateDefaultApplied già true) sostituisce del
    // tutto la richiesta ajax di questo primo passaggio.
    if (!this.dateDefaultApplied) {
      this.dateDefaultApplied = true;

      if (!params.year && !params.month && !params.day) {
        const today = new Date();
        // Il redirect va verso la stessa rotta, cambiando solo i query
        // param: senza l'abort esplicito della transizione in corso, il
        // router genera un TypeError interno ("Cannot read properties of
        // undefined (reading 'name')") perché la transizione verso la
        // rotta corrente non è ancora stata finalizzata quando proviamo a
        // sostituirla (bug noto di Ember, vedi emberjs/ember.js#18577).
        transition.abort();
        this.router.replaceWith("map", {
          queryParams: {
            year: today.getFullYear(),
            month: today.getMonth() + 1,
            day: today.getDate(),
          },
        });
        return;
      }
    }

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
    if (params.year) {
      data.year = params.year;
    }
    if (params.month) {
      data.month = params.month;
    }
    if (params.day) {
      data.day = params.day;
    }

    return ajax("/map-under-dev.json", { data });
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
      controller.set("year", null);
      controller.set("month", null);
      controller.set("day", null);
      this.dateDefaultApplied = false;
    }
  }

  // Titolo della pagina (tab del browser / breadcrumb).
  titleToken() {
    return i18n("discourse_maps.page_title");
  }
}

