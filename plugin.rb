# frozen_string_literal: true

# ============================================================================
#  Discourse Maps
#  Plugin che permette di inserire informazioni geografiche nei topic e di
#  visualizzarle su una mappa interattiva (LocationIQ oppure Google Maps).
#  NOTA: questo file è il punto di ingresso del plugin. In questo primo step
#  contiene solo la struttura di base (metadati, abilitazione, impostazioni).
#  Le funzionalità (composer, pagina /map, filtri) verranno aggiunte nei
#  passaggi successivi.
# ============================================================================

# name: discourse-maps
# about: Associate geographic information in topics and display on an interactive map.
# version: 1.0.0
# authors: Stefano Sisti
# url: https://github.com/sisti86dinova/discourse-maps
# required_version: 2.7.0

# Abilita/disabilita l'intero plugin tramite l'impostazione del pannello admin.
enabled_site_setting :discourse_maps_enabled

# Registra il foglio di stile comune (mappe, layout della pagina /map, ecc.).
register_asset "stylesheets/common/discourse-maps.scss"

# Garantisce che l'icona del link "Mappa" in sidebar sia sempre disponibile,
# indipendentemente dal set di icone di default configurato nel sito.
register_svg_icon "globe"

# Icone del pulsante che apre/chiude i filtri su mobile (pagina /map).
register_svg_icon "angle-up"
register_svg_icon "angle-down"

# Permette al composer di inviare il parametro "discourse_maps_location" alla
# creazione del topic. Lo dichiariamo come :hash perché è un oggetto con più
# campi (indirizzo + coordinate lat/lng).

# ----------------------------------------------------------------------------
#  Blocco di inizializzazione lato server.
# ----------------------------------------------------------------------------
after_initialize do

  add_permitted_post_create_param("discourse_maps_location", :hash)

  # Fa sopravvivere questi parametri nel payload di ReviewableQueuedPost, così
  # da poterli recuperare in on(:approved_post) quando un post di un utente
  # non ancora approvato viene messo in coda di moderazione e il post reale
  # viene creato solo dopo l'ok dello staff (vedi apply_map_metadata sotto).
  NewPostManager.add_plugin_payload_attribute("discourse_maps_location")
  NewPostManager.add_plugin_payload_attribute("discourse_maps_from_map")

  # Namespace del modulo del plugin.
  module ::DiscourseMaps
    PLUGIN_NAME = "discourse-maps"

    # Nome del campo custom del topic in cui salviamo i dati geografici.
    # Contiene: { address, lat, lng, display_name, country, start_date,
    # end_date }. "address" è l'indirizzo digitato dall'utente, gli altri
    # campi di geocoding sono il risultato del provider (il paese arriva già
    # "interpretato", non digitato a mano, per evitare grafie diverse per lo
    # stesso paese). start_date/end_date ("YYYY-MM-DD") sono il periodo di
    # riferimento del topic, anch'esse digitate dall'utente nel modal.
    LOCATION_FIELD = "discourse_maps_location"

    # Restituisce il tag "mappa" configurato nel pannello admin
    # (impostazione `discourse_maps_map_tag_id`), oppure nil se non esiste.
    def self.map_tag
      Tag.find_by(id: SiteSetting.discourse_maps_map_tag_id)
    end

    # Applica al topic i dati geografici e il tag "mappa", a partire dai
    # parametri "discourse_maps_location" / "discourse_maps_from_map".
    # Usato sia alla creazione diretta del post (on :post_created) sia
    # all'approvazione di un post che era in coda di moderazione (on
    # :approved_post), perché in quel secondo caso il post viene ricreato da
    # ReviewableQueuedPost e :post_created non viene emesso.
    def self.apply_map_metadata(topic, location, from_map)
      return if location.blank? && from_map.blank?

      if location.present?
        topic.custom_fields[LOCATION_FIELD] = location
        topic.save_custom_fields(true)
      end

      tag = map_tag
      if tag && topic.tags.exclude?(tag)
        topic.tags << tag
        topic.save!
      end
    end

    # Scope di base: topic con tag "mappa", posizione salvata e visibili
    # all'utente (guardian). Non applica i filtri categoria/tag: è la base
    # sia per l'elenco dei topic sia per calcolare le opzioni dei filtri.
    def self.base_map_scope(guardian)
      tag = map_tag
      return nil unless tag

      topic_ids = TopicCustomField.where(name: LOCATION_FIELD).pluck(:topic_id)
      return nil if topic_ids.empty?

      scope =
        Topic
          .listable_topics
          .secured(guardian)
          .where(id: topic_ids)
          .joins(:topic_tags)
          .where(topic_tags: { tag_id: tag.id }) # vincolo tag "mappa"

      { scope: scope, tag: tag }
    end

    # Filtra uno scope per tag: il topic deve possedere TUTTI i tag indicati.
    def self.filter_by_tags(scope, tag_names)
      Tag
        .where(name: tag_names)
        .pluck(:id)
        .each { |tid| scope = scope.where(id: TopicTag.where(tag_id: tid).select(:topic_id)) }
      scope
    end

    # Filtra uno scope per paese. Il paese è salvato solo dentro il custom
    # field JSON (LOCATION_FIELD), non è una colonna: il confronto va fatto
    # leggendo e parsando il JSON, non con una where SQL.
    def self.filter_by_countries(scope, country_names)
      scope.where(id: topic_ids_matching_countries(scope, country_names))
    end

    def self.topic_ids_matching_countries(scope, country_names)
      TopicCustomField
        .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
        .pluck(:topic_id, :value)
        .select { |_, value| country_names.include?(parse_country(value)) }
        .map(&:first)
    end

    # Elenco (ordinato, senza duplicati) dei paesi presenti tra i topic dello
    # scope indicato.
    def self.countries_for_scope(scope)
      names =
        TopicCustomField
          .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
          .pluck(:value)
          .map { |value| parse_country(value) }
          .reject(&:blank?)
          .uniq
          .sort

      names.map { |name| { id: name, name: name } }
    end

    # Il custom field è salvato come JSON: estrae il paese in modo sicuro
    # (nil se il valore non è presente o non è un JSON valido).
    def self.parse_country(raw_value)
      return nil if raw_value.blank?

      JSON.parse(raw_value)["country"]
    rescue JSON::ParserError
      nil
    end

    # Estrae il periodo (data inizio/fine) dal custom field JSON. Restituisce
    # nil se il valore non è presente/valido o se manca una delle due date:
    # sono obbligatorie entrambe alla creazione, ma i topic salvati prima
    # dell'introduzione di questa feature non le hanno, e semplicemente non
    # compariranno mai nei filtri per data (restano visibili senza filtro).
    def self.parse_date_range(raw_value)
      return nil if raw_value.blank?

      data = JSON.parse(raw_value)
      start_date = data["start_date"]
      end_date = data["end_date"]
      return nil if start_date.blank? || end_date.blank?

      [Date.parse(start_date), Date.parse(end_date)]
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
    end

    # Valida il periodo (inizio/fine) di una posizione così come arriva dal
    # composer (hash con chiavi simbolo o stringa, non ancora serializzato in
    # JSON): entrambe le date devono essere presenti e la fine non deve
    # precedere l'inizio. Usato per il controllo server-side alla creazione
    # del post (vedi NewPostManager.add_handler più sotto), a garanzia
    # dell'invariante anche se il client non validasse correttamente (bug,
    # chiamata diretta alle API, ecc.).
    def self.valid_location_dates?(location)
      start_date = location[:start_date] || location["start_date"]
      end_date = location[:end_date] || location["end_date"]
      return false if start_date.blank? || end_date.blank?

      Date.parse(start_date.to_s) <= Date.parse(end_date.to_s)
    rescue ArgumentError, TypeError
      false
    end

    # Converte i parametri di filtro anno/mese/giorno (eventualmente parziali)
    # nell'intervallo di date corrispondente, usato per il confronto "overlap"
    # con il periodo di ciascun topic. nil se l'anno non è indicato (nessun
    # filtro per data) o se la combinazione non è una data valida.
    def self.date_filter_range(year, month, day)
      return nil if year.blank?

      year = year.to_i

      if month.present?
        month = month.to_i

        if day.present?
          date = Date.new(year, month, day.to_i)
          [date, date]
        else
          start = Date.new(year, month, 1)
          [start, start.end_of_month]
        end
      else
        [Date.new(year, 1, 1), Date.new(year, 12, 31)]
      end
    rescue ArgumentError
      nil
    end

    # Periodi (coppie [inizio, fine]) dei topic dello scope indicato, con
    # periodo valido. Base comune per il calcolo delle opzioni anno/mese/giorno.
    def self.date_ranges_for_scope(scope)
      TopicCustomField
        .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
        .pluck(:value)
        .map { |value| parse_date_range(value) }
        .compact
    end

    # Filtra uno scope per periodo: il topic deve avere un periodo che si
    # sovrappone (overlap) all'intervallo [filter_start, filter_end] indicato.
    def self.filter_by_date_range(scope, filter_start, filter_end)
      scope.where(id: topic_ids_matching_date_range(scope, filter_start, filter_end))
    end

    def self.topic_ids_matching_date_range(scope, filter_start, filter_end)
      TopicCustomField
        .where(topic_id: scope.distinct.pluck("topics.id"), name: LOCATION_FIELD)
        .pluck(:topic_id, :value)
        .select { |_, value|
          range = parse_date_range(value)
          range && range[0] <= filter_end && range[1] >= filter_start
        }
        .map(&:first)
    end

    # Anni disponibili nello scope indicato: un topic il cui periodo attraversa
    # più anni compare in ognuno di essi (coerente con la logica "overlap").
    def self.years_for_scope(scope)
      years =
        date_ranges_for_scope(scope)
          .flat_map { |start_date, end_date| (start_date.year..end_date.year).to_a }
          .uniq
          .sort

      years.map { |year| { id: year, name: year.to_s } }
    end

    # Mesi disponibili nello scope indicato per l'anno selezionato: ogni
    # periodo viene "ritagliato" sui confini dell'anno prima di estrarne i
    # mesi, così un topic che attraversa più anni contribuisce solo con i mesi
    # effettivamente ricadenti in quell'anno.
    def self.months_for_scope(scope, year)
      year_start = Date.new(year, 1, 1)
      year_end = Date.new(year, 12, 31)

      months =
        date_ranges_for_scope(scope)
          .flat_map { |start_date, end_date|
            clipped_start = [start_date, year_start].max
            clipped_end = [end_date, year_end].min
            next [] if clipped_start > clipped_end

            (clipped_start.month..clipped_end.month).to_a
          }
          .uniq
          .sort

      months.map { |month| { id: month, name: month.to_s } }
    end

    # Giorni disponibili nello scope indicato per anno/mese selezionati: stessa
    # logica di ritaglio dei mesi, applicata ai confini del mese.
    def self.days_for_scope(scope, year, month)
      month_start = Date.new(year, month, 1)
      month_end = month_start.end_of_month

      days =
        date_ranges_for_scope(scope)
          .flat_map { |start_date, end_date|
            clipped_start = [start_date, month_start].max
            clipped_end = [end_date, month_end].min
            next [] if clipped_start > clipped_end

            (clipped_start.day..clipped_end.day).to_a
          }
          .uniq
          .sort

      days.map { |day| { id: day, name: day.to_s } }
    end

    # Raccoglie i topic da mostrare nella pagina /map, ordinati per data di
    # creazione decrescente. Rispetta i permessi dell'utente (guardian) e
    # restituisce solo i dati necessari a mappa e lista.
    #
    # Filtri opzionali:
    #   - category_id   : mostra solo i topic della categoria indicata;
    #   - tag_names     : mostra solo i topic che hanno TUTTI i tag indicati
    #                     (il vincolo del tag "mappa" resta sempre applicato);
    #   - country_names : mostra solo i topic il cui indirizzo è in uno dei
    #                     paesi indicati;
    #   - year/month/day: mostra solo i topic il cui periodo (inizio/fine) si
    #                     sovrappone al periodo indicato (anno, anno+mese o
    #                     data esatta a seconda di quali sono presenti).
    def self.map_topics(guardian, category_id: nil, tag_names: [], country_names: [], year: nil, month: nil, day: nil)
      base = base_map_scope(guardian)
      return [] unless base

      scope = base[:scope]

      # Filtro per categoria.
      scope = scope.where(category_id: category_id) if category_id.present?

      # Filtro per tag: il topic deve possedere tutti i tag selezionati.
      scope = filter_by_tags(scope, tag_names) if tag_names.present?

      # Filtro per paese.
      scope = filter_by_countries(scope, country_names) if country_names.present?

      # Filtro per periodo.
      date_range = date_filter_range(year, month, day)
      scope = filter_by_date_range(scope, *date_range) if date_range

      topics = scope.includes(:tags).distinct.order(created_at: :desc).to_a

      # Precarica i custom field per evitare query N+1.
      Topic.preload_custom_fields(topics, [LOCATION_FIELD])

      # Topic già letti (almeno un post) dall'utente corrente, per la classe
      # "visited" nella lista (come nella topic-list nativa).
      visited_topic_ids =
        if guardian.user
          TopicUser
            .where(user_id: guardian.user.id, topic_id: topics.map(&:id))
            .where("last_read_post_number > 0")
            .pluck(:topic_id)
            .to_set
        else
          Set.new
        end

      topics.map do |topic|
        {
          id: topic.id,
          title: topic.title,
          fancy_title: topic.fancy_title,
          url: "/t/#{topic.slug}/#{topic.id}",
          category_id: topic.category_id,
          tags: topic.tags.map(&:name),
          location: topic.custom_fields[LOCATION_FIELD],
          image_url: topic.image_url,
          views: topic.views,
          like_count: topic.like_count,
          posts_count: topic.posts_count,
          last_posted_at: topic.last_posted_at,
          created_at: topic.created_at,
          visited: visited_topic_ids.include?(topic.id),
        }
      end
    end

    # Opzioni disponibili per i filtri categoria/tag/paese/periodo: incrociate
    # tra loro (AND), così che scegliere un filtro aggiorni le opzioni degli
    # altri mostrando solo quelle che non porterebbero a zero risultati con i
    # filtri già impostati. Anno/mese/giorno hanno in più una gerarchia tra
    # loro (il mese dipende dall'anno scelto, il giorno da anno+mese): le
    # opzioni di un livello più specifico sono calcolate solo se il livello
    # superiore è già selezionato.
    def self.map_filter_options(guardian, category_id: nil, tag_names: [], country_names: [], year: nil, month: nil, day: nil)
      base = base_map_scope(guardian)
      return { category_ids: [], tags: [], countries: [], years: [], months: [], days: [] } unless base

      scope = base[:scope]
      tag = base[:tag]
      date_range = date_filter_range(year, month, day)

      # Categorie disponibili: rispettano i filtri tag, paese e periodo già impostati.
      scope_for_categories = scope
      scope_for_categories = filter_by_tags(scope_for_categories, tag_names) if tag_names.present?
      scope_for_categories = filter_by_countries(scope_for_categories, country_names) if country_names.present?
      scope_for_categories = filter_by_date_range(scope_for_categories, *date_range) if date_range
      category_ids = scope_for_categories.distinct.pluck(:category_id).compact

      # Tag disponibili: rispettano i filtri categoria, paese e periodo già impostati.
      scope_for_tags = scope
      scope_for_tags = scope_for_tags.where(category_id: category_id) if category_id.present?
      scope_for_tags = filter_by_countries(scope_for_tags, country_names) if country_names.present?
      scope_for_tags = filter_by_date_range(scope_for_tags, *date_range) if date_range

      tag_ids =
        TopicTag
          .where(topic_id: scope_for_tags.distinct.pluck("topics.id"))
          .where.not(tag_id: tag.id)
          .distinct
          .pluck(:tag_id)

      tags = Tag.where(id: tag_ids).order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }

      # Paesi disponibili: rispettano i filtri categoria, tag e periodo già impostati.
      scope_for_countries = scope
      scope_for_countries = scope_for_countries.where(category_id: category_id) if category_id.present?
      scope_for_countries = filter_by_tags(scope_for_countries, tag_names) if tag_names.present?
      scope_for_countries = filter_by_date_range(scope_for_countries, *date_range) if date_range
      countries = countries_for_scope(scope_for_countries)

      # Anni/mesi/giorni disponibili: rispettano i filtri categoria/tag/paese
      # già impostati (non il periodo stesso, che è gerarchico tra i tre).
      scope_for_dates = scope
      scope_for_dates = scope_for_dates.where(category_id: category_id) if category_id.present?
      scope_for_dates = filter_by_tags(scope_for_dates, tag_names) if tag_names.present?
      scope_for_dates = filter_by_countries(scope_for_dates, country_names) if country_names.present?

      years = years_for_scope(scope_for_dates)
      months = year.present? ? months_for_scope(scope_for_dates, year.to_i) : []
      days = (year.present? && month.present?) ? days_for_scope(scope_for_dates, year.to_i, month.to_i) : []

      { category_ids: category_ids, tags: tags, countries: countries, years: years, months: months, days: days }
    end
  end

  # Registra il tipo del campo custom come JSON: in lettura otterremo un Hash,
  # in scrittura verrà serializzato automaticamente in JSON.
  Topic.register_custom_field_type(::DiscourseMaps::LOCATION_FIELD, :json)

  # --------------------------------------------------------------------------
  #  Verifica server-side, alla creazione del post: un topic geolocalizzato
  #  deve avere sia data di inizio sia data di fine (vedi
  #  DiscourseMaps.valid_location_dates?). Il modal del composer valida già
  #  questo vincolo lato client, ma senza un controllo qui un client diverso
  #  (bug, chiamata diretta alle API) potrebbe comunque creare un topic con
  #  posizione ma senza periodo, che non comparirebbe mai nei filtri per data
  #  di /map-under-dev. Si applica solo alla creazione di un nuovo topic
  #  (manager.args[:topic_id] assente): la posizione/il periodo riguardano
  #  solo il primo post, come la posizione stessa.
  # --------------------------------------------------------------------------
  NewPostManager.add_handler do |manager|
    location = manager.args[:discourse_maps_location] || manager.args["discourse_maps_location"]

    if manager.args[:topic_id].blank? && location.present? && !::DiscourseMaps.valid_location_dates?(location)
      next manager.create_error_result(I18n.t("discourse_maps.errors.missing_dates"))
    end

    nil
  end

  # --------------------------------------------------------------------------
  #  Alla creazione del primo post di un topic:
  #   1. salviamo i dati geografici (se presenti) nel custom field del topic;
  #   2. assegniamo automaticamente il tag "mappa" configurato in admin.
  # --------------------------------------------------------------------------
  on(:post_created) do |post, opts, _user|
    # Ci interessa solo il primo post (il topic vero e proprio).
    next unless post.is_first_post?

    # Il parametro può arrivare con chiave simbolo o stringa: gestiamo entrambi.
    location = opts[:discourse_maps_location] || opts["discourse_maps_location"]
    from_map = opts[:discourse_maps_from_map] || opts["discourse_maps_from_map"]

    # Assegnazione automatica del tag "mappa" (id letto dall'impostazione) e
    # salvataggio della posizione. Il tag viene assegnato anche senza
    # posizione quando il topic è stato creato dal pulsante "Nuovo topic"
    # della pagina /map: il tag group è riservato allo staff, quindi un
    # utente normale non può assegnarlo da solo tramite il composer (il
    # selettore lo nasconde e comunque il server lo filtrerebbe) e senza
    # questo bypass non comparirebbe mai nella lista di /map.
    ::DiscourseMaps.apply_map_metadata(post.topic, location, from_map)
  end

  # --------------------------------------------------------------------------
  #  Caso utenti non ancora approvati (o comunque soggetti a moderazione dei
  #  nuovi topic): il post reale NON viene creato subito, ma viene messo in
  #  coda (ReviewableQueuedPost) e ricreato solo quando lo staff approva.
  #  In quel momento :post_created non viene emesso (viene passato
  #  skip_events) e gli opts custom non arrivano comunque, perché
  #  ReviewableQueuedPost ricostruisce gli opts dal proprio "payload", che di
  #  default contiene solo raw/title/tags/category. Per questo registriamo i
  #  nostri parametri come "plugin payload attribute" (sopravvivono nel
  #  payload) e li applichiamo qui, ad approvazione avvenuta.
  # --------------------------------------------------------------------------
  on(:approved_post) do |reviewable, post|
    next unless post&.is_first_post?

    payload = reviewable.payload || {}
    location = payload["discourse_maps_location"]
    from_map = payload["discourse_maps_from_map"]

    ::DiscourseMaps.apply_map_metadata(post.topic, location, from_map)
  end

  # --------------------------------------------------------------------------
  #  Espone i dati geografici del topic al client (pagina del topic), così da
  #  poter disegnare la mappa. L'attributo viene incluso solo se presente.
  # --------------------------------------------------------------------------
  add_to_serializer(
    :topic_view,
    :discourse_maps_location,
    include_condition: -> { object.topic.custom_fields[::DiscourseMaps::LOCATION_FIELD].present? },
  ) { object.topic.custom_fields[::DiscourseMaps::LOCATION_FIELD] }

  # --------------------------------------------------------------------------
  #  Controller della pagina /map.
  #   - richiesta HTML: avvia l'app Ember (che poi renderizza la pagina);
  #   - richiesta JSON: restituisce i topic con tag mappa + posizione.
  # --------------------------------------------------------------------------
  class ::DiscourseMaps::MapController < ::ApplicationController
    requires_plugin ::DiscourseMaps::PLUGIN_NAME

    # Per il caricamento diretto della pagina (HTML) non è una richiesta XHR.
    skip_before_action :check_xhr, only: [:index]

    def index
      respond_to do |format|
        # Avvia l'applicazione Ember: sarà la rotta client a chiedere il JSON.
        format.html { render "default/empty" }

        # Dati per la mappa e la lista, filtrati per permessi utente e per gli
        # eventuali filtri di categoria/tag passati come parametri di query.
        format.json do
          tag_names = Array(params[:tags]&.split(","))
          country_names = Array(params[:countries]&.split(","))

          topics =
            ::DiscourseMaps.map_topics(
              guardian,
              category_id: params[:category_id],
              tag_names: tag_names,
              country_names: country_names,
              year: params[:year],
              month: params[:month],
              day: params[:day],
            )
          filters =
            ::DiscourseMaps.map_filter_options(
              guardian,
              category_id: params[:category_id],
              tag_names: tag_names,
              country_names: country_names,
              year: params[:year],
              month: params[:month],
              day: params[:day],
            )

          render json: { topics: topics, filters: filters }
        end
      end
    end
  end

  # Registra la rotta /map-under-dev (serve sia l'HTML sia /map-under-dev.json).
  # Path volutamente non intuitivo: la feature è già stata comunicata al
  # committente ma non deve essere raggiungibile dagli utenti prima del
  # rilascio ufficiale (il plugin resta comunque abilitato per continuare lo
  # sviluppo).
  Discourse::Application.routes.append { get "/map-under-dev" => "discourse_maps/map#index" }
end



