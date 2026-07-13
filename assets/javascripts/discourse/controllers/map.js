// ============================================================================
//  Discourse Maps - Controller della pagina /map.
//
//  Gestisce lo stato dei filtri (categoria, tag e paese) come query param,
//  così che siano condivisibili tramite URL e persistano al refresh della
//  pagina.
// ============================================================================

import Controller from "@ember/controller";
import { action } from "@ember/object";

export default class MapController extends Controller {
  // Query param sincronizzati con l'URL.
  queryParams = ["category_id", "tags", "countries"];

  category_id = null;
  // I tag selezionati sono memorizzati come stringa CSV (es. "eventi,news").
  tags = null;
  // I paesi selezionati sono memorizzati come stringa CSV.
  countries = null;

  // Array dei tag selezionati (comodo per il tag chooser).
  get selectedTags() {
    return this.tags ? this.tags.split(",") : [];
  }

  // Paese attualmente selezionato (filtro singolo, come la categoria).
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
}

