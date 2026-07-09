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
# about: Inserisci informazioni geografiche nei topic e visualizzale su una mappa interattiva.
# version: 0.0.1
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

# Permette al composer di inviare il parametro "discourse_maps_location" alla
# creazione del topic. Lo dichiariamo come :hash perché è un oggetto con più
# campi (indirizzo + coordinate lat/lng).

# ----------------------------------------------------------------------------
#  Blocco di inizializzazione lato server.
# ----------------------------------------------------------------------------
after_initialize do

  add_permitted_post_create_param("discourse_maps_location", :hash)

  # Namespace del modulo del plugin.
  module ::DiscourseMaps
    PLUGIN_NAME = "discourse-maps"

    # Nome del campo custom del topic in cui salviamo i dati geografici.
    # Contiene: { street, house_number, postcode, city, country,
    #             lat, lng, display_name }.
    LOCATION_FIELD = "discourse_maps_location"

    # Restituisce il tag "mappa" configurato nel pannello admin
    # (impostazione `discourse_maps_map_tag_id`), oppure nil se non esiste.
    def self.map_tag
      Tag.find_by(id: SiteSetting.discourse_maps_map_tag_id)
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

    # Raccoglie i topic da mostrare nella pagina /map, ordinati per data di
    # creazione decrescente. Rispetta i permessi dell'utente (guardian) e
    # restituisce solo i dati necessari a mappa e lista.
    #
    # Filtri opzionali:
    #   - category_id : mostra solo i topic della categoria indicata;
    #   - tag_names   : mostra solo i topic che hanno TUTTI i tag indicati
    #                   (il vincolo del tag "mappa" resta sempre applicato).
    def self.map_topics(guardian, category_id: nil, tag_names: [])
      base = base_map_scope(guardian)
      return [] unless base

      scope = base[:scope]

      # Filtro per categoria.
      scope = scope.where(category_id: category_id) if category_id.present?

      # Filtro per tag: il topic deve possedere tutti i tag selezionati.
      if tag_names.present?
        Tag
          .where(name: tag_names)
          .pluck(:id)
          .each do |tid|
            scope = scope.where(id: TopicTag.where(tag_id: tid).select(:topic_id))
          end
      end

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

    # Opzioni disponibili per i filtri categoria/tag: incrociate tra loro
    # (AND), così che scegliere una categoria aggiorni le opzioni di tag
    # (e viceversa) mostrando solo quelle che non porterebbero a zero
    # risultati con il filtro già impostato sull'altro campo.
    def self.map_filter_options(guardian, category_id: nil, tag_names: [])
      base = base_map_scope(guardian)
      return { category_ids: [], tags: [] } unless base

      scope = base[:scope]
      tag = base[:tag]

      # Categorie disponibili: rispettano il filtro tag già impostato.
      scope_for_categories = scope
      if tag_names.present?
        Tag
          .where(name: tag_names)
          .pluck(:id)
          .each do |tid|
            scope_for_categories =
              scope_for_categories.where(id: TopicTag.where(tag_id: tid).select(:topic_id))
          end
      end
      category_ids = scope_for_categories.distinct.pluck(:category_id).compact

      # Tag disponibili: rispettano il filtro categoria già impostato.
      scope_for_tags = scope
      scope_for_tags = scope_for_tags.where(category_id: category_id) if category_id.present?

      tag_ids =
        TopicTag
          .where(topic_id: scope_for_tags.select(:id))
          .where.not(tag_id: tag.id)
          .distinct
          .pluck(:tag_id)

      tags = Tag.where(id: tag_ids).order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }

      { category_ids: category_ids, tags: tags }
    end
  end

  # Registra il tipo del campo custom come JSON: in lettura otterremo un Hash,
  # in scrittura verrà serializzato automaticamente in JSON.
  Topic.register_custom_field_type(::DiscourseMaps::LOCATION_FIELD, :json)

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
    next if location.blank?

    topic = post.topic

    # 1. Salvataggio dei dati geografici nel custom field del topic.
    topic.custom_fields[::DiscourseMaps::LOCATION_FIELD] = location
    topic.save_custom_fields(true)

    # 2. Assegnazione automatica del tag "mappa" (id letto dall'impostazione).
    tag = ::DiscourseMaps.map_tag
    if tag && topic.tags.exclude?(tag)
      topic.tags << tag
      topic.save!
    end
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
          topics =
            ::DiscourseMaps.map_topics(
              guardian,
              category_id: params[:category_id],
              tag_names: Array(params[:tags]&.split(",")),
            )
          filters =
            ::DiscourseMaps.map_filter_options(
              guardian,
              category_id: params[:category_id],
              tag_names: Array(params[:tags]&.split(",")),
            )

          render json: { topics: topics, filters: filters }
        end
      end
    end
  end

  # Registra la rotta /map (serve sia l'HTML sia /map.json).
  Discourse::Application.routes.append { get "/map" => "discourse_maps/map#index" }
end



