// ============================================================================
//  Discourse Maps - Componente della pagina /map.
//
//  Mostra:
//    1. in alto, una mappa interattiva con un pin per ogni topic geolocalizzato
//       (popup con titolo, categoria, tag e link al topic);
//    2. sotto, la lista dei topic corrispondenti.
//
//  Argomenti:
//    @topics - array di topic ({ id, title, fancy_title, url, category_id,
//              tags, location }) fornito dalla rotta /map.
// ============================================================================

import Component from "@glimmer/component";
import { service } from "@ember/service";
import { i18n } from "discourse-i18n";
import DiscourseMapsMap from "./discourse-maps-map";

export default class MapPage extends Component {
  @service site;

  // Restituisce il nome della categoria dato il suo id (o null).
  categoryName(categoryId) {
    if (!categoryId) {
      return null;
    }
    const category = this.site.categories?.find((c) => c.id === categoryId);
    return category ? category.name : null;
  }

  // Solo i topic che hanno una posizione valida.
  get locatedTopics() {
    return (this.args.topics || []).filter(
      (t) => t.location && t.location.lat && t.location.lng
    );
  }

  // Marker per la mappa, con popup HTML (titolo + categoria + tag + link).
  get markers() {
    return this.locatedTopics.map((topic) => {
      const parts = [
        `<strong><a href="${topic.url}">${topic.fancy_title || topic.title}</a></strong>`,
      ];

      const category = this.categoryName(topic.category_id);
      if (category) {
        parts.push(category);
      }

      if (topic.tags?.length) {
        parts.push(topic.tags.join(", "));
      }

      return {
        lat: topic.location.lat,
        lng: topic.location.lng,
        popupHtml: parts.join("<br>"),
      };
    });
  }

  // Righe per la lista sotto la mappa, con nome categoria già risolto.
  get rows() {
    return this.locatedTopics.map((topic) => ({
      topic,
      category: this.categoryName(topic.category_id),
      tags: topic.tags || [],
    }));
  }

  <template>
    <div class="discourse-maps-page">
      <h1 class="discourse-maps-page__title">{{i18n "discourse_maps.page_title"}}</h1>

      {{! Mappa con tutti i pin. }}
      <DiscourseMapsMap @markers={{this.markers}} @interactive={{true}} />

      {{! Lista dei topic geolocalizzati. }}
      <div class="discourse-maps-list">
        {{#each this.rows as |row|}}
          <div class="discourse-maps-list__item">
            <a href={{row.topic.url}} class="discourse-maps-list__title">
              {{row.topic.title}}
            </a>

            <div class="discourse-maps-list__meta">
              {{#if row.category}}
                <span class="discourse-maps-list__category">{{row.category}}</span>
              {{/if}}

              {{#each row.tags as |tag|}}
                <span class="discourse-maps-list__tag">{{tag}}</span>
              {{/each}}
            </div>
          </div>
        {{else}}
          <p class="discourse-maps-list__empty">
            {{i18n "discourse_maps.list.empty"}}
          </p>
        {{/each}}
      </div>
    </div>
  </template>
}

