# frozen_string_literal: true

# ============================================================================
#  Discourse Maps
#  Plugin che permette di inserire informazioni geografiche nei topic e di
#  visualizzarle su una mappa interattiva (LocationIQ oppure Google Maps).
#
#  NOTA: questo file è il punto di ingresso del plugin. In questo primo step
#  contiene solo la struttura di base (metadati, abilitazione, impostazioni).
#  Le funzionalità (composer, pagina /map, filtri) verranno aggiunte nei
#  passaggi successivi.
# ============================================================================

# name: discourse-maps
# about: Inserisci informazioni geografiche nei topic e visualizzale su una mappa interattiva.
# meta_topic_id: TODO
# version: 0.0.1
# authors: TODO
# url: https://example.com/discourse-maps
# required_version: 2.7.0

# Abilita/disabilita l'intero plugin tramite l'impostazione del pannello admin.
enabled_site_setting :discourse_maps_enabled

# Registra il foglio di stile comune (mappe, layout della pagina /map, ecc.).
register_asset "stylesheets/common/discourse-maps.scss"

# Permette al composer di inviare il parametro "discourse_maps_location" alla
# creazione del topic. Lo dichiariamo come :hash perché è un oggetto con più
# campi (indirizzo + coordinate lat/lng).
add_permitted_post_create_param("discourse_maps_location", :hash)

# ----------------------------------------------------------------------------
#  Blocco di inizializzazione lato server.
# ----------------------------------------------------------------------------
after_initialize do
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

    # Raccoglie i topic da mostrare nella pagina /map: quelli che hanno il tag
    # "mappa" e che contengono dati geografici. Rispetta i permessi dell'utente
    # (guardian) e restituisce solo i dati necessari a mappa e lista.
    #
    # Filtri opzionali:
    #   - category_id : mostra solo i topic della categoria indicata;
    #   - tag_names   : mostra solo i topic che hanno TUTTI i tag indicati
    #                   (il vincolo del tag "mappa" resta sempre applicato).
    def self.map_topics(guardian, category_id: nil, tag_names: [])
      tag = map_tag
      return [] unless tag

      # Id dei topic che hanno effettivamente una posizione salvata.
      topic_ids = TopicCustomField.where(name: LOCATION_FIELD).pluck(:topic_id)
      return [] if topic_ids.empty?

      scope =
        Topic
          .listable_topics
          .secured(guardian)
          .where(id: topic_ids)
          .joins(:topic_tags)
          .where(topic_tags: { tag_id: tag.id }) # vincolo tag "mappa"

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

      topics = scope.includes(:tags).distinct.to_a

      # Precarica i custom field per evitare query N+1.
      Topic.preload_custom_fields(topics, [LOCATION_FIELD])

      topics.map do |topic|
        {
          id: topic.id,
          title: topic.title,
          fancy_title: topic.fancy_title,
          url: "/t/#{topic.slug}/#{topic.id}",
          category_id: topic.category_id,
          tags: topic.tags.map(&:name),
          location: topic.custom_fields[LOCATION_FIELD],
        }
      end
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

          render json: { topics: topics }
        end
      end
    end
  end

  # Registra la rotta /map (serve sia l'HTML sia /map.json).
  Discourse::Application.routes.append { get "/map" => "discourse_maps/map#index" }
end



