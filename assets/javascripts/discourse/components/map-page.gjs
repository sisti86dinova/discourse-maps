// ============================================================================
//  Discourse Maps - Componente della pagina /map.
//
//  Mostra:
//    1. in alto, i filtri (categoria + tag, solo quelli effettivamente
//       presenti tra i topic elencati, per evitare filtraggi a vuoto);
//    2. una mappa interattiva con un pin per ogni topic geolocalizzato
//       (popup con titolo, categoria, tag e link al topic);
//    3. sotto, la lista dei topic corrispondenti (ordinati per data di
//       creazione decrescente), caricata a gruppi di 10 mentre si scrolla.
//
//  Argomenti:
//    @topics          - array di topic ({ id, title, fancy_title, url,
//                       category_id, tags, location, ... }) dalla rotta /map,
//                       già ordinati dal server (più recenti prima).
//    @filters          - { category_ids: [...], tags: [{id, name}, ...] },
//                        opzioni dei filtri calcolate dal server sulla base
//                        dei topic effettivamente mostrabili.
//    @categoryId      - id della categoria attualmente selezionata (filtro).
//    @selectedTags    - array dei tag attualmente selezionati (filtro).
//    @onChangeCategory - callback(categoryId) al cambio del filtro categoria.
//    @onChangeTags     - callback(tags[]) al cambio del filtro tag.
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { htmlSafe } from "@ember/template";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { i18n } from "discourse-i18n";
import { relativeAge } from "discourse/lib/formatter";
import icon from "discourse/helpers/d-icon";
import DiscourseMapsMap from "./discourse-maps-map";

// Quanti topic mostrare per volta nella lista (caricamento a scroll).
const PAGE_SIZE = 10;

export default class MapPage extends Component {
  @service site;

  @tracked visibleCount = PAGE_SIZE;

  observer = null;

  // Nuovo risultato dal server (nuovi filtri): la paginazione riparte da
  // capo. Eseguito da {{didUpdate}}, fuori dal ciclo di tracking del
  // render, per non incorrere nell'errore di backtracking di Ember.
  resetPaging = () => {
    this.visibleCount = PAGE_SIZE;
  };

  // Restituisce la categoria (con url e nome) dato il suo id (o null).
  category(categoryId) {
    if (!categoryId) {
      return null;
    }
    return this.site.categories?.find((c) => c.id === categoryId) || null;
  }

  // Categorie da proporre nel filtro: solo quelle presenti tra i topic
  // mostrabili (indicate dal server), non tutte quelle del forum.
  get availableCategories() {
    const ids = this.args.filters?.category_ids || [];
    return (this.site.categories || [])
      .filter((c) => ids.includes(c.id))
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  // Tag da proporre nel filtro: solo quelli presenti tra i topic
  // mostrabili (indicati dal server).
  get availableTags() {
    return this.args.filters?.tags || [];
  }

  get categoryIdString() {
    return this.args.categoryId ? String(this.args.categoryId) : "";
  }

  // Un solo tag selezionabile per volta, come la categoria.
  get selectedTagName() {
    return (this.args.selectedTags && this.args.selectedTags[0]) || "";
  }

  get hasActiveFilters() {
    return Boolean(this.args.categoryId) || Boolean(this.selectedTagName);
  }

  handleCategoryChange = (event) => {
    const value = event.target.value;
    this.args.onChangeCategory(value ? parseInt(value, 10) : null);
  };

  handleTagChange = (event) => {
    const value = event.target.value;
    this.args.onChangeTags(value ? [value] : []);
  };

  resetFilters = () => {
    this.args.onChangeCategory(null);
    this.args.onChangeTags([]);
  };

  // Solo i topic che hanno una posizione valida (per mappa e lista). La
  // mappa mostra sempre l'intero risultato filtrato, indipendentemente
  // dalla paginazione della lista sotto.
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

      const category = this.category(topic.category_id);
      if (category) {
        parts.push(category.name);
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

  // Righe per la lista sotto la mappa: categoria/tag come link, statistiche
  // (viste, like, commenti, attività) come nella topic-list nativa.
  get rows() {
    return this.locatedTopics.map((topic) => {
      const category = this.category(topic.category_id);

      return {
        topic,
        category,
        categoryStyle: category
          ? htmlSafe(
              `--category-badge-color: #${category.color};--category-badge-text-color: #${category.text_color};`
            )
          : null,
        tags: (topic.tags || []).map((tag) => ({
          name: tag,
          url: `/tag/${tag}`,
        })),
        commentsCount: Math.max((topic.posts_count || 1) - 1, 0),
        activityDate: topic.last_posted_at
          ? relativeAge(new Date(topic.last_posted_at), { addAgo: false })
          : null,
      };
    });
  }

  // Sottoinsieme di righe effettivamente visibili (paginazione a scroll).
  get visibleRows() {
    return this.rows.slice(0, this.visibleCount);
  }

  get hasMore() {
    return this.visibleCount < this.rows.length;
  }

  loadMore = () => {
    if (this.hasMore) {
      this.visibleCount = Math.min(this.visibleCount + PAGE_SIZE, this.rows.length);
    }
  };

  // Osserva la sentinella in fondo alla lista: quando entra nel viewport,
  // carica il prossimo gruppo di topic (come uno scroll infinito).
  setupObserver = (element) => {
    this.observer = new IntersectionObserver((entries) => {
      if (entries[0]?.isIntersecting) {
        this.loadMore();
      }
    });
    this.observer.observe(element);
  };

  teardownObserver = () => {
    this.observer?.disconnect();
    this.observer = null;
  };

  <template>
    <div class="discourse-maps-page" {{didUpdate this.resetPaging @topics}}>
      <h1 class="discourse-maps-page__title">{{i18n "discourse_maps.page_title"}}</h1>

      {{! Filtri: categoria e tag, solo quelli presenti tra i topic elencati. }}
      <div class="discourse-maps-filters">
        <select
          class="discourse-maps-filters__category"
          value={{this.categoryIdString}}
          {{on "change" this.handleCategoryChange}}
        >
          <option value="">{{i18n "discourse_maps.filters.all_categories"}}</option>
          {{#each this.availableCategories as |cat|}}
            <option value={{cat.id}}>{{cat.name}}</option>
          {{/each}}
        </select>

        <select
          class="discourse-maps-filters__tags"
          value={{this.selectedTagName}}
          {{on "change" this.handleTagChange}}
        >
          <option value="">{{i18n "discourse_maps.filters.all_tags"}}</option>
          {{#each this.availableTags as |tag|}}
            <option value={{tag.name}}>{{tag.name}}</option>
          {{/each}}
        </select>

        {{#if this.hasActiveFilters}}
          <button
            type="button"
            class="discourse-maps-filters__reset"
            {{on "click" this.resetFilters}}
          >
            {{i18n "discourse_maps.filters.reset"}}
          </button>
        {{/if}}
      </div>

      {{! Mappa con tutti i pin del risultato filtrato. }}
      <DiscourseMapsMap @markers={{this.markers}} @interactive={{true}} />

      {{! Lista dei topic geolocalizzati (ordinati per data, paginata a scroll). }}
      <div class="discourse-maps-list">
        {{#each this.visibleRows as |row|}}
          <div class="discourse-maps-list__item">
            {{#if row.topic.image_url}}
              <div class="discourse-maps-list__thumbnail">
                <a href={{row.topic.url}} role="img" aria-label={{row.topic.title}}>
                  <img src={{row.topic.image_url}} loading="lazy" alt="" />
                </a>
              </div>
            {{/if}}

            <div class="discourse-maps-list__stats">
              <span class="discourse-maps-list__stat">
                {{icon "eye"}}<span class="number">{{row.topic.views}}</span>
              </span>
              <span class="discourse-maps-list__stat">
                {{icon "heart"}}<span class="number">{{row.topic.like_count}}</span>
              </span>
              <span class="discourse-maps-list__stat">
                {{icon "comment"}}<span class="number">{{row.commentsCount}}</span>
              </span>
              {{#if row.activityDate}}
                <a href={{row.topic.url}} class="discourse-maps-list__stat post-activity">
                  <span class="relative-date">{{row.activityDate}}</span>
                </a>
              {{/if}}
            </div>

            <div class="discourse-maps-list__content">
              <a href={{row.topic.url}} class="discourse-maps-list__title">
                {{row.topic.title}}
              </a>

              <div class="discourse-maps-list__meta">
                {{#if row.category}}
                  <a
                    class="badge-category__wrapper"
                    style={{row.categoryStyle}}
                    href={{row.category.url}}
                  >
                    <span class="badge-category --style-square">
                      <span class="badge-category__name">{{row.category.name}}</span>
                    </span>
                  </a>
                {{/if}}

                {{#if row.tags.length}}
                  <ul class="discourse-tags" aria-label="Tags">
                    {{#each row.tags as |tag|}}
                      <li><a href={{tag.url}} class="discourse-tag simple">{{tag.name}}</a></li>
                    {{/each}}
                  </ul>
                {{/if}}
              </div>
            </div>
          </div>
        {{else}}
          <p class="discourse-maps-list__empty">
            {{i18n "discourse_maps.list.empty"}}
          </p>
        {{/each}}

        {{#if this.hasMore}}
          <div
            class="discourse-maps-list__sentinel"
            {{didInsert this.setupObserver}}
            {{willDestroy this.teardownObserver}}
          ></div>
        {{/if}}
      </div>
    </div>
  </template>
}
