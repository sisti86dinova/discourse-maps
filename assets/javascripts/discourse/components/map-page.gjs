// ============================================================================
//  Discourse Maps - Componente della pagina /map.
//
//  Mostra:
//    1. in alto, una mappa interattiva con un pin per ogni topic geolocalizzato
//       (popup con titolo, categoria, tag e link al topic);
//    2. sotto, la lista dei topic corrispondenti.
//
//  Argomenti:
//    @topics          - array di topic ({ id, title, fancy_title, url,
//                       category_id, tags, location }) dalla rotta /map.
//    @categoryId      - id della categoria attualmente selezionata (filtro).
//    @selectedTags    - array dei tag attualmente selezionati (filtro).
//    @onChangeCategory - callback(categoryId) al cambio del filtro categoria.
//    @onChangeTags     - callback(tags[]) al cambio del filtro tag.
// ============================================================================

import Component from "@glimmer/component";
import { service } from "@ember/service";
import { hash } from "@ember/helper";
import { htmlSafe } from "@ember/template";
import { i18n } from "discourse-i18n";
import { relativeAge } from "discourse/lib/formatter";
import icon from "discourse/helpers/d-icon";
import CategoryChooser from "select-kit/components/category-chooser";
import TagChooser from "select-kit/components/tag-chooser";
import DiscourseMapsMap from "./discourse-maps-map";

export default class MapPage extends Component {
  @service site;

  // Restituisce la categoria (con url e nome) dato il suo id (o null).
  category(categoryId) {
    if (!categoryId) {
      return null;
    }
    return this.site.categories?.find((c) => c.id === categoryId) || null;
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

  <template>
    <div class="discourse-maps-page">
      <h1 class="discourse-maps-page__title">{{i18n "discourse_maps.page_title"}}</h1>

      {{! Filtri: categoria e tag (il tag "mappa" resta sempre applicato lato server). }}
      <div class="discourse-maps-filters">
        <CategoryChooser
          @value={{@categoryId}}
          @onChange={{@onChangeCategory}}
          @options={{hash none="discourse_maps.filters.all_categories"}}
          class="discourse-maps-filters__category"
        />

        <TagChooser
          @tags={{@selectedTags}}
          @onChange={{@onChangeTags}}
          @everyTag={{true}}
          @options={{hash filterPlaceholder="discourse_maps.filters.tags_placeholder"}}
          class="discourse-maps-filters__tags"
        />
      </div>

      {{! Mappa con tutti i pin. }}
      <DiscourseMapsMap @markers={{this.markers}} @interactive={{true}} />

      {{! Lista dei topic geolocalizzati. }}
      <div class="discourse-maps-list">
        {{#each this.rows as |row|}}
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
      </div>
    </div>
  </template>
}

