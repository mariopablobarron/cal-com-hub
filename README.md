# Cal.com self-hosted — HUB Startidea

Fase 0 de la migración: Cal.com **RECUPERADO 2026-08-08** en
`cal.hubstartidea.es`, preservando la base de datos existente.

## ⚠️ DEUDA TÉCNICA CRÍTICA — leer antes de tocar nada ⚠️

**NO uses "Redeploy Stack" desde la UI de Coolify.** Coolify v3 con
buildPack=compose tiene 3 bugs combinados que rompen Cal.com:

1. Ignora valores literales en `environment:` del yml (solo `${VAR}` del panel)
2. Strip las labels Traefik del yml (no autogenera para multi-service compose)
3. Cachea `Application.dockerComposeFile` en BD y no refresca de GitHub

**Si faltan los tres contenedores pero siguen los volúmenes**, usa
`scripts/recover-cal-stack.sh`. Valida primero la web en una red interna y solo
la conecta a Traefik cuando está sana:

```bash
# El fichero debe contener todos los secretos y tener modo 0600.
sudo scripts/recover-cal-stack.sh /ruta/segura/cal.env
```

**Si solo necesitas actualizar cal-web (versión nueva, env nueva, etc.)**:
1. Edita `docker-compose.yml` local
2. `git push` (queda registrado pero NO triggera nada útil)
3. Ejecuta el script de recreate manual en el VPS:

```bash
# Desde el VPS root@72.61.195.108
scp /Users/STARTIDEA/cal-com-hub/scripts/recreate-cal-web.py root@72.61.195.108:/tmp/
ssh root@72.61.195.108 'docker inspect cmpaiat5n0004qfa4r6m8l8rl-cal-web > /tmp/cal-web-snapshot.json && python3 /tmp/recreate-cal-web.py'
```

El script:
- Lee el container actual para preservar env vars y volumes
- Lo borra
- Lo recrea con docker run + labels Traefik manuales + labels Coolify
- Network: `coolify`
- Healthcheck: `/` (NO `/api/health` que es 404 en v6.2.0)

## Estado actual

- [x] DNS `cal.hubstartidea.es` → `72.61.195.108` (Hostinger)
- [x] App Coolify creada (id `cmpaiat5n0004qfa4r6m8l8rl`)
- [x] 20 variables de entorno cifradas en Coolify BD, incluida la contraseña SMTP
- [x] cal-web LIVE con labels Traefik manuales (workaround)
- [x] cert Let's Encrypt OK
- [x] Registro admin existente, onboarding completado y 3 tipos de evento
- [x] Backup SQL local válido y cron diario confirmado
- [ ] Verificar manualmente la contraseña de acceso del admin
- [ ] Test booking end-to-end y entrega de email, con autorización expresa
- [ ] Conectar Google Calendar con credenciales OAuth dedicadas
- [ ] Fase 1: POC sala Sócrates

La recuperación previa a los cambios está en
`/root/cal-recovery-20260808T130500Z` en KVM8: instantánea offline de los dos
volúmenes, manifiesto SHA-256, configuración anterior para rollback y copia de
la base de Coolify antes de rotar secretos. El directorio y sus ficheros
sensibles tienen permisos restrictivos.

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

En **Environment Variables** de la app, añadir el contrato completo de
`.env.example`. Son 19 variables: tres para PostgreSQL, dos URLs de conexión,
tres URLs públicas, dos secretos de aplicación, seis de SMTP y tres de runtime.
Las sensibles deben marcarse como secretas.

| Key | Type |
|---|---|
| `NEXTAUTH_SECRET`, `CALENDSO_ENCRYPTION_KEY` | Secret, runtime |
| `POSTGRES_PASSWORD` | Secret, runtime |
| `DATABASE_URL`, `DATABASE_DIRECT_URL` | Secret, runtime |
| `EMAIL_SERVER_PASSWORD` | Secret, runtime |
| Resto de `.env.example` | Runtime |

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

### 6. Crear primer usuario admin (solo instalaciones nuevas)

Visitar `https://cal.hubstartidea.es/auth/setup` — Cal.com lleva un wizard de
primer uso que crea el admin. **No repetir este paso en la instalación actual**:
el registro ya existe y la raíz redirige al login.

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

## Secrets

**⚠️ No guardar valores reales en Git.** Deben vivir únicamente en el gestor de
secretos de la infraestructura y en el fichero de recuperación `0600` de la VPS.

Generar valores nuevos durante la instalación o una rotación controlada:

```bash
NEXTAUTH_SECRET="$(openssl rand -hex 32)"
CALENDSO_ENCRYPTION_KEY="$(openssl rand -hex 16)" # exactamente 32 caracteres
POSTGRES_PASSWORD="$(openssl rand -hex 24)"
```

La API key de Resend debe obtenerse del gestor de secretos; nunca copiarse al
repo. Cal.com la recibe como `EMAIL_SERVER_PASSWORD` para SMTP, no como una
variable `RESEND_API_KEY` separada.

## Verificación tras deploy

```bash
# La raíz redirige al login cuando ya existe admin; siguiendo el redirect da 200.
curl -sSL -o /dev/null -w '%{http_code}\n' https://cal.hubstartidea.es/

# Verificar que el HTML carga
curl -s https://cal.hubstartidea.es | head -20

# Logs de cal-web en Coolify (Logs tab) para ver "Ready in Xms"
```

## Rollback si algo falla

Cal.com es completamente independiente del HUB. Para una reversión recuperable:

1. Detener únicamente los tres contenedores `cmpaiat5n0004qfa4r6m8l8rl-cal-*`.
2. Restaurar configuración y datos desde `/root/cal-recovery-20260808T130500Z`.
3. No borrar DNS, la app de Coolify ni los volúmenes como parte de un rollback.

**No usar Delete en Coolify**: puede eliminar volúmenes y convertir una
reversión sencilla en una restauración completa.

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
