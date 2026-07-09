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
end



