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

# ----------------------------------------------------------------------------
#  Blocco di inizializzazione lato server.
#  Qui, negli step successivi, aggiungeremo:
#   - la serializzazione dei dati geografici nei topic;
#   - gli endpoint per il geocoding / il recupero dei topic con tag mappa;
#   - l'associazione automatica del tag "mappa" (id: 295).
# ----------------------------------------------------------------------------
after_initialize do
  # Namespace del modulo del plugin (segnaposto per la logica futura).
  module ::DiscourseMaps
    PLUGIN_NAME = "discourse-maps"

    # ID del tag "mappa" a cui i topic vengono associati automaticamente.
    # Coincide con l'impostazione `discourse_maps_map_tag_id`; qui teniamo
    # un valore di riferimento di default.
    MAP_TAG_ID = 295
  end

  # TODO (step successivi): controller, rotte, serializer, event handlers.
end

