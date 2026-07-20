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
//    @filters          - { category_ids: [...], tags: [{id, name}, ...],
//                        countries: [{id, name}, ...] }, opzioni dei filtri
//                        calcolate dal server sulla base dei topic
//                        effettivamente mostrabili.
//    @categoryId      - id della categoria attualmente selezionata (filtro).
//    @selectedTags    - array dei tag attualmente selezionati (filtro).
//    @countryName     - paese attualmente selezionato (filtro).
//    @onChangeCategory - callback(categoryId) al cambio del filtro categoria.
//    @onChangeTags     - callback(tags[]) al cambio del filtro tag.
//    @onChangeCountry  - callback(countryName) al cambio del filtro paese.
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { htmlSafe } from "@ember/template";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { i18n } from "discourse-i18n";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import ComboBox from "discourse/select-kit/components/combo-box";
import DiscourseMapsMap from "./discourse-maps-map";

// Quanti topic mostrare per volta nella lista (caricamento a scroll).
const PAGE_SIZE = 10;

// Colore di fallback per il pin sulla mappa quando il topic non ha una
// categoria (o la categoria non ha un colore).
const DEFAULT_MARKER_COLOR = "#0088CC";

// Soglie per il formato relativo (secondi -> unità), stesso approccio della
// ricetta MDN per Intl.RelativeTimeFormat: nessuna dipendenza esterna, quindi
// nessun rischio di ereditare un "Invalid date" da altre utility.
const RELATIVE_TIME_DIVISIONS = [
  { amount: 60, unit: "second" },
  { amount: 60, unit: "minute" },
  { amount: 24, unit: "hour" },
  { amount: 7, unit: "day" },
  { amount: 4.34524, unit: "week" },
  { amount: 12, unit: "month" },
  { amount: Number.POSITIVE_INFINITY, unit: "year" },
];

export default class MapPage extends Component {
  @service site;
  @service siteSettings;
  @service currentUser;
  @service composer;

  @tracked visibleCount = PAGE_SIZE;

  // Su mobile i filtri sono racchiusi in un blocco richiudibile (collapse),
  // chiuso di default: si aprono con il pulsante "Filtri" sotto il titolo.
  // Su desktop il pulsante è nascosto via CSS e i filtri sono sempre visibili.
  @tracked filtersExpanded = false;

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

  // Righe del ComboBox categoria: quando la categoria ha un'icona (badge
  // style "icona"), select-kit disegna un <svg><use href="#nome"></use></svg>
  // dentro la riga (.select-kit-row), ma senza alcun colore: qui generiamo
  // una regola CSS per riga (scoped su data-value, l'id della categoria) che
  // colora quell'icona con il colore nativo della categoria. Niente da
  // validare sull'id (è sempre un numero); il colore invece arriva
  // dall'admin di Discourse, quindi lo controlliamo comunque prima di
  // interpolarlo in CSS.
  get categoryRowIconStyles() {
    const rules = this.availableCategories
      .filter((c) => /^[0-9a-fA-F]{3,8}$/.test(c.color || ""))
      .map(
        (c) =>
          `.discourse-maps-filters__category .select-kit-row[data-value="${c.id}"] svg use { fill: #${c.color}; }`
      )
      .join("\n");
    return htmlSafe(rules);
  }

  // Valore per il ComboBox categoria: @categoryId arriva dalla query string
  // (quindi sempre come stringa), ma gli id delle categorie sono numeri. Senza
  // questa conversione il ComboBox non trova la riga corrispondente e mostra
  // l'id al posto del nome. Se l'id non è (più) tra quelli disponibili
  // torniamo null invece di mostrare un valore che non può essere risolto.
  get categoryIdValue() {
    const raw = this.args.categoryId;
    if (raw === null || raw === undefined || raw === "") {
      return null;
    }
    const id = Number(raw);
    return this.availableCategories.some((c) => c.id === id) ? id : null;
  }

  // Tag da proporre nel filtro: solo quelli presenti tra i topic mostrabili
  // (indicati dal server come oggetti { id, name }). Vanno passati così (non
  // semplificati a un array di sole stringhe) perché il ComboBox:
  //  - deduplica il contenuto internamente usando item[valueProperty]: su
  //    stringhe pure quella chiave è sempre undefined per ognuna (le
  //    collasserebbe tutte su una voce sola);
  //  - se si disabilita valueProperty per evitare la dedup, il valore
  //    selezionato diventa un array (content.filter(...)) invece di un
  //    elemento singolo, e la label non si risolve più (resta vuota).
  // Con @valueProperty="name" nel template la chiave di dedup e di
  // confronto è il nome (univoco per riga): nessuno dei due problemi si
  // presenta.
  get availableTags() {
    return this.args.filters?.tags || [];
  }

  // Un solo tag selezionabile per volta, come la categoria. Torniamo null se
  // il tag non è (più) tra quelli disponibili.
  get selectedTagName() {
    const name = (this.args.selectedTags && this.args.selectedTags[0]) || null;
    return name && this.availableTags.some((t) => t.name === name) ? name : null;
  }

  // Paesi da proporre nel filtro: solo quelli presenti tra i topic
  // mostrabili (indicati dal server come oggetti { id, name }), per lo
  // stesso motivo dei tag (sopra).
  get availableCountries() {
    return this.args.filters?.countries || [];
  }

  // Paese selezionato: null se non è (più) tra quelli disponibili.
  get selectedCountryName() {
    const name = this.args.countryName || null;
    return name && this.availableCountries.some((c) => c.name === name) ? name : null;
  }

  // Un filtro è "attivo" in base allo stato passato dalla rotta (URL), non in
  // base a cosa il ComboBox riesce a mostrare: altrimenti, se il valore
  // selezionato non è (più) tra le opzioni disponibili, il filtro
  // risulterebbe attivo (i topic restano filtrati) ma il pulsante di reset
  // resterebbe disabilitato.
  get hasActiveFilters() {
    return (
      Boolean(this.args.categoryId) ||
      Boolean(this.args.selectedTags && this.args.selectedTags.length) ||
      Boolean(this.args.countryName)
    );
  }

  // Quanti filtri sono attivi: mostrato nel pulsante di toggle su mobile,
  // così l'utente sa che ci sono filtri applicati anche a blocco chiuso.
  get activeFilterCount() {
    let count = 0;
    if (this.args.categoryId) {
      count++;
    }
    if (this.args.selectedTags && this.args.selectedTags.length) {
      count++;
    }
    if (this.args.countryName) {
      count++;
    }
    return count;
  }

  get filtersToggleLabel() {
    const base = i18n("discourse_maps.filters.toggle");
    return this.activeFilterCount ? `${base} (${this.activeFilterCount})` : base;
  }

  toggleFilters = () => {
    this.filtersExpanded = !this.filtersExpanded;
  };

  handleCategoryChange = (value) => {
    this.args.onChangeCategory(value ?? null);
  };

  handleTagChange = (value) => {
    this.args.onChangeTags(value ? [value] : []);
  };

  handleCountryChange = (value) => {
    this.args.onChangeCountry(value ?? null);
  };

  // Il pulsante "Nuovo topic" è visibile solo agli admin e ai membri dei
  // gruppi indicati nell'impostazione discourse_maps_new_topic_groups
  // (elenco di id gruppo separati da "|", vuoto = solo admin).
  get canCreateTopic() {
    const user = this.currentUser;
    if (!user) {
      return false;
    }
    if (user.admin) {
      return true;
    }

    const allowedGroupIds = (this.siteSettings.discourse_maps_new_topic_groups || "")
      .split("|")
      .filter(Boolean)
      .map(Number);
    if (!allowedGroupIds.length) {
      return false;
    }

    return (user.groups || []).some((g) => allowedGroupIds.includes(g.id));
  }

  @action
  createTopic() {
    this.composer.openNewTopic();
  }

  resetFilters = () => {
    this.args.onChangeCategory(null);
    this.args.onChangeTags([]);
    this.args.onChangeCountry(null);
  };

  // Solo i topic che hanno una posizione valida (per mappa e lista). La
  // mappa mostra sempre l'intero risultato filtrato, indipendentemente
  // dalla paginazione della lista sotto.
  get locatedTopics() {
    return (this.args.topics || []).filter(
      (t) => t.location && t.location.lat && t.location.lng
    );
  }

  // Marker per la mappa, con popup HTML (titolo + categoria + tag, entrambi
  // cliccabili). Il titolo ha una classe dedicata (discourse-maps-popup__title)
  // per poterlo stilizzare separatamente dal resto del contenuto del popup.
  get markers() {
    return this.locatedTopics.map((topic) => {
      const category = this.category(topic.category_id);

      // Il titolo è già "display: block" via CSS: un <br> dopo aggiungerebbe
      // solo una riga vuota in più. Va unito senza <br>, mentre categoria e
      // tag (se entrambi presenti) restano separati da <br>, una riga ciascuno.
      const title =
        `<strong class="discourse-maps-popup__title">` +
        `<a href="${topic.url}">${topic.fancy_title || topic.title}</a>` +
        `</strong>`;

      const lines = [];
      if (category) {
        lines.push(
          `${i18n("discourse_maps.popup.category")} ` +
            `<a href="${category.url}">${category.name}</a>`
        );
      }

      if (topic.tags?.length) {
        const tagLinks = topic.tags
          .map((tag) => `<a href="/tag/${tag}">${tag}</a>`)
          .join(", ");
        lines.push(`${i18n("discourse_maps.popup.tags")} ${tagLinks}`);
      }

      return {
        lat: topic.location.lat,
        lng: topic.location.lng,
        popupHtml: title + lines.join("<br>"),
        color: category?.color ? `#${category.color}` : DEFAULT_MARKER_COLOR,
      };
    });
  }

  // Righe per la lista sotto la mappa: categoria/tag come link, statistiche
  // (viste, like, commenti, attività) come nella topic-list nativa.
  get rows() {
    return this.locatedTopics.map((topic) => {
      const category = this.category(topic.category_id);
      const tags = topic.tags || [];

      // Classi "category-<slug>"/"tag-<slug>" sull'item della lista, utili a
      // temi/CSS esterni per personalizzare l'aspetto in base a categoria e
      // tag (lo slug del tag in Discourse è il nome stesso del tag).
      const itemClass = [
        category?.slug ? `category-${category.slug}` : null,
        ...tags.map((tag) => `tag-${tag}`),
      ]
        .filter(Boolean)
        .join(" ");

      return {
        topic,
        category,
        itemClass,
        categoryStyle: category
          ? htmlSafe(
              `--category-badge-color: #${category.color};--category-badge-text-color: #${category.text_color};`
            )
          : null,
        tags: tags.map((tag) => ({
          name: tag,
          url: `/tag/${tag}`,
        })),
        commentsCount: Math.max((topic.posts_count || 1) - 1, 0),
        activityDate: this.formatActivityDate(topic),
      };
    });
  }

  // Data di attività mostrata nella lista: preferisce l'ultimo post, con
  // fallback alla creazione del topic. Se il valore ricevuto non è una data
  // valida non la mostriamo, invece di rischiare un "Invalid date". Il
  // formato relativo è calcolato qui (Intl.RelativeTimeFormat nativo),
  // senza dipendere da altre utility di date.
  formatActivityDate(topic) {
    const raw = topic.last_posted_at || topic.created_at;
    if (!raw) {
      return null;
    }

    const date = new Date(raw);
    const time = date.getTime();
    if (Number.isNaN(time)) {
      return null;
    }

    let duration = (time - Date.now()) / 1000;

    for (const division of RELATIVE_TIME_DIVISIONS) {
      if (Math.abs(duration) < division.amount) {
        const formatter = new Intl.RelativeTimeFormat(
          document.documentElement.lang || undefined,
          { numeric: "auto" }
        );
        return formatter.format(Math.round(duration), division.unit);
      }
      duration /= division.amount;
    }

    return null;
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

      {{! Riga di azioni visibile solo su mobile (nascosta via CSS su
          desktop): il toggle apre/chiude il blocco dei filtri sottostante,
          "Nuovo post" resta sempre visibile (non è dentro il blocco che si
          può richiudere) all'estremo opposto della stessa riga. }}
      <div class="discourse-maps-mobile-actions">
        <DButton
          @action={{this.toggleFilters}}
          @icon={{if this.filtersExpanded "angle-up" "angle-down"}}
          @translatedLabel={{this.filtersToggleLabel}}
          aria-expanded={{if this.filtersExpanded "true" "false"}}
          aria-controls="discourse-maps-filters"
          class="btn-default discourse-maps-filters-toggle"
        />

        {{#if this.canCreateTopic}}
          <DButton
            @icon="far-pen-to-square"
            @label="discourse_maps.filters.new_topic"
            @action={{this.createTopic}}
            class="btn btn-icon-text d-combo-button-button btn-default
              discourse-maps-filters__new-topic discourse-maps-filters__new-topic--mobile"
          />
        {{/if}}
      </div>

      {{! Filtri: categoria e tag, solo quelli presenti tra i topic elencati.
          Su mobile "is-collapsed" li nasconde finché non si usa il toggle. }}
      <div
        id="discourse-maps-filters"
        class="discourse-maps-filters {{unless this.filtersExpanded 'is-collapsed'}}"
      >
        <style>{{this.categoryRowIconStyles}}</style>

        <ComboBox
          @value={{this.categoryIdValue}}
          @content={{this.availableCategories}}
          @onChange={{this.handleCategoryChange}}
          @options={{hash none="discourse_maps.filters.all_categories"}}
          class="discourse-maps-filters__category"
        />

        <ComboBox
          @value={{this.selectedTagName}}
          @content={{this.availableTags}}
          @onChange={{this.handleTagChange}}
          @valueProperty="name"
          @options={{hash none="discourse_maps.filters.all_tags"}}
          class="discourse-maps-filters__tags"
        />

        <ComboBox
          @value={{this.selectedCountryName}}
          @content={{this.availableCountries}}
          @onChange={{this.handleCountryChange}}
          @valueProperty="name"
          @options={{hash none="discourse_maps.filters.all_countries"}}
          class="discourse-maps-filters__countries"
        />

        <button
          type="button"
          class="btn btn-icon-text d-page-action-button btn-small btn-danger discourse-maps-filters__reset
            {{unless this.hasActiveFilters 'disabled'}}"
          disabled={{if this.hasActiveFilters false true}}
          {{on "click" this.resetFilters}}
        >
          {{i18n "discourse_maps.filters.reset"}}
        </button>

        {{#if this.canCreateTopic}}
          <DButton
            @icon="far-pen-to-square"
            @label="discourse_maps.filters.new_topic"
            @action={{this.createTopic}}
            class="btn btn-icon-text d-combo-button-button btn-default discourse-maps-filters__new-topic"
          />
        {{/if}}
      </div>

      {{! Mappa con tutti i pin del risultato filtrato. }}
      <DiscourseMapsMap @markers={{this.markers}} @interactive={{true}} />

      {{! Lista dei topic geolocalizzati (ordinati per data, paginata a scroll). }}
      <div class="discourse-maps-list">
        {{#each this.visibleRows as |row|}}
          <div class="discourse-maps-list__item {{row.itemClass}} {{if row.topic.visited 'visited'}}">
            <div class="discourse-maps-list__thumbnail">
              <a href={{row.topic.url}} role="img" aria-label={{row.topic.title}}>
                {{#if row.topic.image_url}}
                  <img src={{row.topic.image_url}} loading="lazy" alt="" />
                {{else}}
                  <div class="thumbnail-placeholder">
                    {{icon "comments"}}
                  </div>
                {{/if}}
              </a>
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
                <span class="discourse-maps-list__relative-date">{{row.activityDate}}</span>
              {{/if}}
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
