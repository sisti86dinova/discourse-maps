// ============================================================================
//  Discourse Maps - Controller della pagina /map.
//
//  Gestisce lo stato dei filtri (categoria, tag e paese) come query param,
//  così che siano condivisibili tramite URL e persistano al refresh della
//  pagina.
// ============================================================================

import Controller from "@ember/controller";
import { action, computed } from "@ember/object";

export default class MapController extends Controller {
  // Query param sincronizzati con l'URL.
  queryParams = ["category_id", "tags", "countries", "year", "month", "day"];

  category_id = null;
  // I tag selezionati sono memorizzati come stringa CSV (es. "eventi,news").
  tags = null;
  // I paesi selezionati sono memorizzati come stringa CSV.
  countries = null;
  // Filtro per periodo: anno, mese (1-12) e giorno, gerarchici (il mese ha
  // senso solo con un anno selezionato, il giorno solo con anno+mese). Alla
  // primissima apertura della pagina la rotta li valorizza con la data
  // odierna (vedi routes/map.js), per evitare di mostrare tutti i topic
  // geolocalizzati in una volta sola.
  year = null;
  month = null;
  day = null;

  // Array dei tag selezionati (comodo per il tag chooser).
  //
  // @computed con dipendenza esplicita su "tags": un getter nativo (senza
  // @computed) su un Controller classico NON viene ri-eseguito quando
  // this.tags cambia via this.set(), perché legge la proprietà con un
  // semplice this.tags invece di un accesso tracciato da Ember. Il risultato
  // resterebbe quindi bloccato al valore calcolato al primo render, anche se
  // l'URL e il modello si aggiornano correttamente.
  @computed("tags")
  get selectedTags() {
    return this.tags ? this.tags.split(",") : [];
  }

  // Paese attualmente selezionato (filtro singolo, come la categoria). Stessa
  // ragione di sopra per il @computed("countries") esplicito.
  @computed("countries")
  get countryName() {
    return this.countries ? this.countries.split(",")[0] : null;
  }

  // Aggiorna il filtro categoria.
  @action
  updateCategory(categoryId) {
    this.set("category_id", categoryId || null);
  }

  // Aggiorna il filtro tag (riceve un array, lo salviamo come CSV).
  @action
  updateTags(tags) {
    this.set("tags", tags?.length ? tags.join(",") : null);
  }

  // Aggiorna il filtro paese.
  @action
  updateCountry(countryName) {
    this.set("countries", countryName || null);
  }

  // Aggiorna il filtro anno. Cambiare l'anno rende potenzialmente non validi
  // mese e giorno già selezionati (potrebbero non esistere come opzioni per
  // il nuovo anno): li azzeriamo sempre, l'utente li riseleziona se servono.
  @action
  updateYear(year) {
    this.set("year", year || null);
    this.set("month", null);
    this.set("day", null);
  }

  // Aggiorna il filtro mese. Stesso ragionamento di updateYear per il giorno.
  @action
  updateMonth(month) {
    this.set("month", month || null);
    this.set("day", null);
  }

  // Aggiorna il filtro giorno.
  @action
  updateDay(day) {
    this.set("day", day || null);
  }

  // Riporta il filtro periodo alla data odierna (usato dal pulsante "Rimuovi
  // filtri"): a differenza di updateYear, imposta anno/mese/giorno tutti
  // insieme invece di azzerare mese/giorno, perché qui vogliamo tornare al
  // giorno corrente, non semplicemente rimuovere il filtro.
  @action
  resetDateFilter() {
    const today = new Date();
    this.set("year", today.getFullYear());
    this.set("month", today.getMonth() + 1);
    this.set("day", today.getDate());
  }
}

