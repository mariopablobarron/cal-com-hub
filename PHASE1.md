# Fase 1 — POC con sala Sócrates

Objetivo: validar que Cal.com encaja conceptualmente con "reservar una
sala física" antes de migrar las otras 4 + tarifas por rol.

**Time budget**: 2h máximo. Si pasamos, paramos y reevaluamos.

## Cómo se modela una sala en Cal.com

Cal.com no tiene concepto nativo de "Resource" o "Room". Las salas se
modelan como **Event Types** del usuario admin (`mario`).

Mapeo HUB → Cal.com:

| Concepto HUB | Cal.com equivalent |
|---|---|
| Sala física (Sócrates) | Event Type "Sala Sócrates · 1h" |
| Reserva por horas | Event con `length: 60` y disponibilidad horaria |
| Aforo | `seatsPerTimeSlot` (Cal.com llama a esto "Group Bookings") |
| Confirmación admin | `requiresConfirmation: true` |
| Notas del cliente | Standard "Additional notes" field |
| Tarifa | Stripe app + `price` por event-type |

## Event Type del POC

```yaml
title: "Sala Sócrates · 1 hora"
slug: socrates-1h
description: |
  Sala de reuniones para 8 personas. Mesa cuadrada, pantalla,
  pizarra. Reserva en horas completas (HH:00).

length: 60                          # 1 hora exacto
hidden: false                       # pública
position: 1                         # primera en el listado

# Disponibilidad
availability:
  monday-friday: 09:00-21:00
  saturday: 10:00-14:00
  sunday: closed
beforeEventBuffer: 0
afterEventBuffer: 0
slotInterval: 60                    # solo HH:00, no HH:30
minimumBookingNotice: 240           # 4h de antelación mínima

# Aforo / formato
seatsPerTimeSlot: 1                 # sala individual, no group event

# Confirmación
requiresConfirmation: false         # auto-confirm (cambiar si quieres aprobar)

# Location
locations:
  - type: inPerson
    address: "C/ Conde Cifuentes 33, Granada — Sala Sócrates"

# Custom fields (preguntas pre-booking)
customInputs:
  - label: "¿Para qué vas a usar la sala?"
    type: textLong
    required: true
  - label: "¿Cuántas personas asistirán?"
    type: number
    required: true

# Notificaciones
workflows:
  - reminder 24h before (email)
  - reminder 1h before (email)
  - thank you after event (email)
```

## Pasos manuales en Cal.com UI

Cuando `cal.hubstartidea.es` esté arriba:

1. Login como `mario`
2. **Event Types** → **+ New**
3. Type: **Standard**
4. Rellenar como el YAML anterior
5. **Limits** tab: `Minimum booking notice = 4 hours`
6. **Apps** tab: por ahora SIN Stripe (vendrá en Fase 2)
7. **Save** → URL pública: `cal.hubstartidea.es/mario/socrates-1h`

## Tests del POC (los hago yo via Playwright)

1. Abrir `cal.hubstartidea.es/mario/socrates-1h` como visitor
2. Verificar slots disponibles solo en HH:00 dentro del horario
3. Reservar slot mañana 16:00
4. Rellenar campos custom (uso + asistentes)
5. Confirmar booking → verificar email
6. Como admin: ver booking en `cal.hubstartidea.es/bookings`
7. Cancelar booking
8. Verificar que el slot vuelve a estar disponible

## Decisión post-POC

Antes de Fase 2, evaluar honestamente:

- ✅ ¿La UI te convence vs el `/reservar` actual?
- ✅ ¿El flow de campos custom + email + admin view funciona?
- ✅ ¿Tu Calendar de Google sincroniza bien?
- ❓ Si todo es ✅: arrancamos Fase 2 (5 salas × 3 roles = 15 event-types)
- ❌ Si hay un ❌ grave: paramos, custom queda intacto, lo discutimos

## Fase 2 preview (lo que pinta más complejo)

Las 3 tarifas por rol se modelarán como 3 event-types separados por
sala, ocultos detrás de URLs no-listadas:

| URL pública | Visible | Stripe price | Audiencia |
|---|---|---|---|
| `/socrates-1h` | sí | 15€/h | Visitantes/clientes |
| `/socrates-1h-coworker` | hidden | 10.50€/h (-30%) | Coworkers (link en `/me`) |
| `/socrates-1h-collaborator` | hidden | 12€/h (-20%) | Colaboradores (link en `/me`) |

El `/me` del HUB detectará el role del user y le dará el link correcto.
Esto requiere mantener un mapping `room_slug × role → cal_event_url` en
nuestro código.

**Alternativa más clean** (Fase 2 alt): single event-type por sala +
webhook on booking.created que aplica descuento via Stripe coupon
generado on-the-fly. Más limpio conceptualmente pero más infra.

Decidimos en Fase 2.
