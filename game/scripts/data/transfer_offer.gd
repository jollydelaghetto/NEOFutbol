class_name TransferOffer
extends RefCounted

## Identificador estable de la oferta.
var offer_id: String = ""

## Identificador estable del club comprador: String conocido o null.
var buyer_id = null

## Identificador estable del club vendedor: String conocido o null.
var seller_id = null

## Identificador estable de la temporada de emisión.
var season_id: String = ""

## Jugador originalmente ofertado: String conocido o null; conservar sin cambios.
var original_player_id = null

## Importe original: int en unidades económicas internas, nunca float, o null.
## Conservar sin cambios; no recalcular al confirmar la venta.
var offered_amount = null

## Estado: "pending", "accepted", "rejected", "expired" o "consumed"; null si desconocido.
## "accepted" no implica transferencia ejecutada; "consumed" indica oferta ya utilizada.
var status = null

## Caducidad en el calendario simulado: String YYYY-MM-DD conocido o null.
var expires_at = null
