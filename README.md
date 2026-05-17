# Cal.com self-hosted — HUB Startidea

Fase 0 de la migración: Cal.com vivo en `cal.hubstartidea.es`, sin tocar
la web actual (`hubstartidea.es`).

## Estado actual

- [x] DNS `cal.hubstartidea.es` → `72.61.195.108` (Hostinger, propagado)
- [x] `docker-compose.yml` preparado con Cal.com v6.2.0 + Postgres 16 + Redis 7
- [x] Secrets generados (ver más abajo)
- [ ] App creada en Coolify
- [ ] FQDN `cal.hubstartidea.es` configurado en Coolify
- [ ] Deploy + healthcheck verde
- [ ] Usuario admin creado (Mario)
- [ ] Test booking end-to-end

## Pasos en Coolify (orden estricto)

### 1. Crear nueva app

Coolify → **New Resource** → **Docker Compose Empty**

- **Name**: `cal-com-hub`
- **Project**: nuevo o "Startidea apps"
- **Server**: el VPS Hostinger (72.61.195.108)

### 2. Pegar el docker-compose

En el editor de Compose, pegar el contenido de `docker-compose.yml` de
esta carpeta.

### 3. Setear Environment Variables

En **Environment Variables** de la app, añadir estas 4 (ver valores
generados en la sección "Secrets" más abajo):

| Key | Type |
|---|---|
| `NEXTAUTH_SECRET` | Build-time + runtime |
| `CALENDSO_ENCRYPTION_KEY` | Build-time + runtime |
| `POSTGRES_PASSWORD` | Build-time + runtime |
| `RESEND_API_KEY` | Build-time + runtime |

**⚠️ Coolify v3 quoting bug**: si algún valor contiene `<`, `>` o
espacios, envolver con comillas simples `'...'`. Los que generé no
tienen caracteres problemáticos, pero atento al `RESEND_API_KEY` que
copies del HUB.

### 4. Configurar FQDN

En **Configuration** del servicio `cal-web`:
- **Domain**: `cal.hubstartidea.es`
- **Port**: `3000`
- **HTTPS**: ON (Coolify gestiona Let's Encrypt automáticamente)

### 5. Deploy

Click **Deploy**. Tardará 3-5 minutos:
1. Pull de la imagen `calcom/cal.com:v6.2.0` (~1GB)
2. Pull de `postgres:16-alpine` y `redis:7-alpine`
3. Start de los 3 servicios
4. `prisma migrate deploy` automático al primer arranque de cal-web
5. Healthcheck verde

### 6. Crear primer usuario admin

Visitar `https://cal.hubstartidea.es/auth/setup` — Cal.com lleva un
wizard de primer-uso que crea el admin.

- **Email**: mariopablobarron@gmail.com
- **Username**: `mario` (será tu URL: `cal.hubstartidea.es/mario`)
- **Password**: la que prefieras
- **Timezone**: Europe/Madrid

### 7. Conectar Google Calendar

Settings → Integrations → Google Calendar → Connect.

⚠️ Cal.com necesita Google OAuth credentials para el conector. Como ya
tenemos GSC OAuth (reference_dns_startidea_ionos no, mejor:
ref de luciérnaga), podemos reusar el client_id/client_secret O crear
unos nuevos para Cal.com en Google Cloud Console.

Yo recomiendo nuevos credentials (separación de responsabilidades).
Te lo explico cuando lleguemos a este paso.

## Secrets generados

**⚠️ NO commitear estos valores. Pegar directamente en Coolify.**

```
NEXTAUTH_SECRET=40d354837b55ac682e1ceb7473825df867d6fc24e110b51f3cfe8717f69ab71a
CALENDSO_ENCRYPTION_KEY=988f3afa4552ebf3831f06afb203b7b8
POSTGRES_PASSWORD=2e66c8f52f47d5181ac5521ceb01a5ddf7efd966383bc385
RESEND_API_KEY=<copiar del hub-startidea-web Coolify env: re_...>
```

## Verificación tras deploy

```bash
# Healthcheck (debe devolver 200)
curl -I https://cal.hubstartidea.es/api/health

# Verificar que el HTML carga
curl -s https://cal.hubstartidea.es | head -20

# Logs de cal-web en Coolify (Logs tab) para ver "Ready in Xms"
```

## Rollback si algo falla

Cal.com es completamente independiente del HUB:
- Coolify → app `cal-com-hub` → **Stop** o **Delete**
- DNS: borrar el A record `cal.hubstartidea.es` (vía Hostinger MCP)
- Volúmenes Docker (`cal-db-data`, `cal-redis-data`) sobreviven a Stop
  pero se borran al Delete

El web actual `hubstartidea.es` NO se ve afectado en ningún momento.

## Próximos pasos (después de Fase 0)

- **Fase 1**: POC con sala Sócrates (1 event-type, sin pricing por rol)
- **Fase 2**: 5 salas + 3 tarifas por rol = 15 event-types
- **Fase 3**: Apuntar `/reservar` del HUB → Cal.com
- **Fase 4**: Bonos prepago (decisión: matar — recuperable después)
- **Fase 5**: Deprecar custom (2 semanas en producción)
- **Fase 6**: Borrar tablas `Booking`, `Pricing`, `PrepaidBond`

Mientras tanto las dos rutas conviven y el custom sigue funcionando.

## Recursos

- Cal.com self-host docs: https://cal.com/docs/self-hosting
- Cal.com source: https://github.com/calcom/cal.com
- Cal.com release notes v6: https://github.com/calcom/cal.com/releases
- License: MIT con commercial terms para Teams >3 users (no aplica aquí)
