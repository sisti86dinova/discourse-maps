// ============================================================================
//  Discourse Maps - Filtro data della pagina /map (anno / mese / giorno).
//
//  Sostituisce 3 combobox separate con un unico controllo "a pillola" che
//  apre un pannello (bottom sheet su mobile, popover ancorato su desktop)
//  con selezione progressiva: anno -> mese -> giorno, ognuno opzionale (si
//  può fermarsi a un livello qualsiasi, come nei picker "tipo Skyscanner").
//
//  Argomenti:
//    @year/@month/@day       - valori attualmente selezionati (Number o null).
//    @availableYears         - [{id, name}] anni con topic geolocalizzati.
//    @availableMonths        - [{id, name}] mesi disponibili per @year
//                              (name già localizzato, vedi map-page.gjs).
//    @availableDays          - [{id, name}] giorni disponibili per @year+@month.
//    @onSelectYear/@onSelectMonth/@onSelectDay - callback(value|null).
// ============================================================================

import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { i18n } from "discourse-i18n";
import icon from "discourse/helpers/d-icon";

export default class DiscourseMapsDateFilter extends Component {
  @tracked isOpen = false;
  // null = nessuno step forzato: si usa lo step "naturale" (il primo livello
  // ancora da scegliere, o il giorno se tutto è già impostato). Impostato
  // esplicitamente quando l'utente clicca una tab o seleziona un valore.
  @tracked activeStep = null;

  get effectiveStep() {
    if (this.activeStep) {
      return this.activeStep;
    }
    if (!this.args.year) {
      return "year";
    }
    if (!this.args.month) {
      return "month";
    }
    return "day";
  }

  get isYearStep() {
    return this.effectiveStep === "year";
  }

  get isMonthStep() {
    return this.effectiveStep === "month";
  }

  get isDayStep() {
    return this.effectiveStep === "day";
  }

  get monthTabDisabled() {
    return !this.args.year;
  }

  get dayTabDisabled() {
    return !this.args.month;
  }

  // Etichetta del pulsante che apre il pannello: solo le parti effettivamente
  // selezionate (anno / anno+mese / anno+mese+giorno), localizzata.
  get triggerLabel() {
    const { year, month, day } = this.args;
    if (!year) {
      return i18n("discourse_maps.filters.date_placeholder");
    }

    const options = { year: "numeric" };
    if (month) {
      options.month = "long";
    }
    if (month && day) {
      options.day = "numeric";
    }

    const formatter = new Intl.DateTimeFormat(
      document.documentElement.lang || undefined,
      options
    );
    return formatter.format(new Date(year, (month || 1) - 1, day || 1));
  }

  // Etichette dei giorni della settimana (Lun...Dom), localizzate: 1 gennaio
  // 2024 era un lunedì, usato solo come riferimento per calcolare i nomi.
  get weekdayLabels() {
    const formatter = new Intl.DateTimeFormat(
      document.documentElement.lang || undefined,
      { weekday: "short" }
    );
    const labels = [];
    for (let i = 0; i < 7; i++) {
      labels.push(formatter.format(new Date(2024, 0, 1 + i)));
    }
    return labels;
  }

  // Griglia del calendario per @year/@month: settimane da lunedì a domenica,
  // celle vuote (null) per il padding iniziale/finale. Un giorno è
  // selezionabile solo se presente in @availableDays (ha topic geolocalizzati).
  get calendarWeeks() {
    const year = this.args.year;
    const month = this.args.month;
    if (!year || !month) {
      return [];
    }

    const availableSet = new Set((this.args.availableDays || []).map((d) => d.id));
    const daysInMonth = new Date(year, month, 0).getDate();
    const firstWeekday = new Date(year, month - 1, 1).getDay();
    const leadingBlanks = (firstWeekday + 6) % 7;

    const cells = new Array(leadingBlanks).fill(null);
    for (let day = 1; day <= daysInMonth; day++) {
      cells.push({
        day,
        available: availableSet.has(day),
        selected: this.args.day === day,
        isToday: this.isToday(year, month, day),
      });
    }
    while (cells.length % 7 !== 0) {
      cells.push(null);
    }

    const weeks = [];
    for (let i = 0; i < cells.length; i += 7) {
      weeks.push(cells.slice(i, i + 7));
    }
    return weeks;
  }

  isToday(year, month, day) {
    const today = new Date();
    return (
      today.getFullYear() === year &&
      today.getMonth() + 1 === month &&
      today.getDate() === day
    );
  }

  isSelected = (candidateId, currentValue) => candidateId === currentValue;

  toggle = () => {
    if (this.isOpen) {
      this.close();
    } else {
      this.open();
    }
  };

  open = () => {
    this.activeStep = null;
    this.isOpen = true;
  };

  close = () => {
    this.isOpen = false;
  };

  handleKeydown = (event) => {
    if (event.key === "Escape") {
      this.close();
    }
  };

  goToYearStep = () => {
    this.activeStep = "year";
  };

  goToMonthStep = () => {
    if (!this.monthTabDisabled) {
      this.activeStep = "month";
    }
  };

  goToDayStep = () => {
    if (!this.dayTabDisabled) {
      this.activeStep = "day";
    }
  };

  selectYear = (yearId) => {
    this.args.onSelectYear(yearId);
    this.activeStep = "month";
  };

  selectMonth = (monthId) => {
    this.args.onSelectMonth(monthId);
    this.activeStep = "day";
  };

  // Selezionare un giorno è l'azione più specifica possibile: chiudiamo il
  // pannello, non c'è altro livello su cui proseguire.
  selectDay = (day) => {
    this.args.onSelectDay(day);
    this.close();
  };

  <template>
    <div class="discourse-maps-date-filter" ...attributes>
      <button
        type="button"
        class="btn btn-default discourse-maps-date-filter__trigger"
        aria-expanded={{if this.isOpen "true" "false"}}
        {{on "click" this.toggle}}
      >
        {{icon "calendar"}}
        <span class="discourse-maps-date-filter__trigger-label">{{this.triggerLabel}}</span>
        {{icon (if this.isOpen "angle-up" "angle-down")}}
      </button>

      {{#if this.isOpen}}
        <div
          class="discourse-maps-date-filter__backdrop"
          {{on "click" this.close}}
        ></div>

        <div
          class="discourse-maps-date-filter__panel"
          role="dialog"
          aria-label={{i18n "discourse_maps.filters.date_placeholder"}}
          {{on "keydown" this.handleKeydown}}
        >
          <div class="discourse-maps-date-filter__panel-header">
            <div class="discourse-maps-date-filter__tabs">
              <button
                type="button"
                class="discourse-maps-date-filter__tab {{if this.isYearStep 'active'}}"
                {{on "click" this.goToYearStep}}
              >
                {{i18n "discourse_maps.filters.all_years"}}
              </button>
              <button
                type="button"
                class="discourse-maps-date-filter__tab {{if this.isMonthStep 'active'}}"
                disabled={{this.monthTabDisabled}}
                {{on "click" this.goToMonthStep}}
              >
                {{i18n "discourse_maps.filters.all_months"}}
              </button>
              <button
                type="button"
                class="discourse-maps-date-filter__tab {{if this.isDayStep 'active'}}"
                disabled={{this.dayTabDisabled}}
                {{on "click" this.goToDayStep}}
              >
                {{i18n "discourse_maps.filters.all_days"}}
              </button>
            </div>

            <button
              type="button"
              class="discourse-maps-date-filter__close"
              aria-label={{i18n "discourse_maps.filters.date_close"}}
              {{on "click" this.close}}
            >
              {{icon "xmark"}}
            </button>
          </div>

          <div class="discourse-maps-date-filter__body">
            {{#if this.isYearStep}}
              <div class="discourse-maps-date-filter__grid">
                {{#each @availableYears as |year|}}
                  <button
                    type="button"
                    class="discourse-maps-date-filter__chip
                      {{if (this.isSelected year.id @year) 'active'}}"
                    {{on "click" (fn this.selectYear year.id)}}
                  >
                    {{year.name}}
                  </button>
                {{/each}}
              </div>
            {{else if this.isMonthStep}}
              <div class="discourse-maps-date-filter__grid">
                {{#each @availableMonths as |month|}}
                  <button
                    type="button"
                    class="discourse-maps-date-filter__chip
                      {{if (this.isSelected month.id @month) 'active'}}"
                    {{on "click" (fn this.selectMonth month.id)}}
                  >
                    {{month.name}}
                  </button>
                {{/each}}
              </div>
            {{else}}
              <div class="discourse-maps-date-filter__day-step">
                <div class="discourse-maps-date-filter__calendar">
                  <div class="discourse-maps-date-filter__weekdays">
                    {{#each this.weekdayLabels as |label|}}
                      <span>{{label}}</span>
                    {{/each}}
                  </div>
                  {{#each this.calendarWeeks as |week|}}
                    <div class="discourse-maps-date-filter__week">
                      {{#each week as |cell|}}
                        {{#if cell}}
                          <button
                            type="button"
                            class="discourse-maps-date-filter__day
                              {{if cell.selected 'active'}}
                              {{if cell.isToday 'today'}}"
                            disabled={{unless cell.available true false}}
                            {{on "click" (fn this.selectDay cell.day)}}
                          >
                            {{cell.day}}
                          </button>
                        {{else}}
                          <span class="discourse-maps-date-filter__day discourse-maps-date-filter__day--empty"></span>
                        {{/if}}
                      {{/each}}
                    </div>
                  {{/each}}
                </div>
              </div>
            {{/if}}
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
