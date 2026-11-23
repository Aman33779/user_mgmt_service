# Aufgabe 5: Deployment auf DigitalOcean

Bei jedem Push auf `main` baut GitHub Actions das Backend-Image, legt es in der GitHub Container Registry (GHCR) ab und startet die Container per SSH mit Docker Compose auf dem Droplet.

```
git push main
   └─ GitHub Actions
        ├─ Job "build":  Dockerfile bauen -> ghcr.io/aman33779/user_mgmt_service:<commit>
        └─ Job "deploy": .env aus GitHub Secrets erzeugen
                         docker-compose.yml + .env per SCP aufs Droplet
                         per SSH: docker compose pull && docker compose up -d
```

Warum das Image in GitHub Actions gebaut wird und nicht auf dem Droplet: Der Gradle-Build braucht viel RAM. Auf einem kleinen Droplet (1 GB) bricht er oft ab. So holt sich das Droplet nur noch das fertige Image.

## Was sich im Repository ändert

| Datei | Änderung |
|---|---|
| `.github/workflows/deploy.yml` | Neu: Pipeline mit den Jobs `build` und `deploy` |
| `docker-compose.yml` | Traefik-Dashboard abgesichert (kein `api.insecure`, kein Port 8081 mehr, Login per BasicAuth über `https://traefik.<DOMAIN>`). Das Backend-Image ist über `BACKEND_IMAGE` einstellbar. |
| `.env` (lokal, nicht im Git) | Neue Variable `TRAEFIK_DASHBOARD_AUTH` |

## Schritt 1: Domain festlegen

Für Let's Encrypt braucht ihr einen Namen, der auf die IP des Droplets zeigt. Dafür gibt es zwei Möglichkeiten:

- **Eigene Domain:** zwei DNS A Records auf die Droplet-IP anlegen, `meinedomain.ch` und `traefik.meinedomain.ch`.
- **Ohne eigene Domain (gratis):** [sslip.io](https://sslip.io). `164-90-12-34.sslip.io` zeigt automatisch auf `164.90.12.34`, und `traefik.164-90-12-34.sslip.io` ebenfalls. Let's Encrypt stellt dafür ein gültiges Zertifikat aus, und ihr braucht nichts einzurichten.

## Schritt 2: Droplet erstellen

1. DigitalOcean, dann **Create > Droplets**
2. Image: **Marketplace > "Docker on Ubuntu"**. Darin sind Docker und das Compose-Plugin schon installiert.
3. Size: Basic, 1 GB RAM reicht
4. Authentication: **SSH Key**. Füge deinen persönlichen Public Key hinzu (`type $HOME\.ssh\id_ed25519.pub` in PowerShell).
5. Notiere dir die öffentliche IPv4, zum Beispiel `164.90.12.34`

## Schritt 3: Droplet vorbereiten (einmalig)

Auf deinem PC (PowerShell) einen eigenen Schlüssel nur für GitHub Actions erzeugen. Das Passwort leer lassen:

```powershell
ssh-keygen -t ed25519 -C "github-actions-deploy" -f $HOME\.ssh\do_deploy
```

Dann einloggen:

```powershell
ssh root@164.90.12.34
```

Auf dem Droplet einen Deploy-User anlegen, der Docker benutzen darf, und den neuen Public Key hinterlegen:

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG docker deploy
mkdir -p /home/deploy/.ssh
nano /home/deploy/.ssh/authorized_keys      # Inhalt von do_deploy.pub einfügen, speichern
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh && chmod 600 /home/deploy/.ssh/authorized_keys

mkdir -p /opt/user_mgmt_service
chown deploy:deploy /opt/user_mgmt_service

# Firewall: nur SSH, HTTP, HTTPS
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

docker compose version    # Kontrolle
```

`do_deploy.pub` zeigst du in PowerShell mit `type $HOME\.ssh\do_deploy.pub` an.

Test vom PC aus:

```powershell
ssh -i $HOME\.ssh\do_deploy deploy@164.90.12.34 "docker ps"
```

## Schritt 4: Passwort-Hash für das Traefik-Dashboard

```powershell
docker run --rm httpd:2.4-alpine htpasswd -nbB admin "DEIN_DASHBOARD_PASSWORT"
```

Die Ausgabe sieht so aus: `admin:$2y$05$....`. Diese ganze Zeile ist der Wert für `TRAEFIK_DASHBOARD_AUTH`.

Für den lokalen Betrieb die Zeile in die lokale `.env` eintragen, **in einfachen Anführungszeichen**:

```
TRAEFIK_DASHBOARD_AUTH='admin:$2y$05$....'
```

Lokal ist das Dashboard danach unter `https://traefik.localhost` erreichbar (und nicht mehr unter `localhost:8081`).

## Schritt 5: GitHub Secrets anlegen

Im Repository unter **Settings > Secrets and variables > Actions > New repository secret**:

| Secret | Wert |
|---|---|
| `SSH_HOST` | IP des Droplets, z. B. `164.90.12.34` |
| `SSH_USER` | `deploy` |
| `SSH_PRIVATE_KEY` | ganzer Inhalt von `$HOME\.ssh\do_deploy` (die Datei **ohne** `.pub`, inklusive der BEGIN- und END-Zeile) |
| `DOMAIN` | z. B. `164-90-12-34.sslip.io` oder `meinedomain.ch` |
| `ACME_EMAIL` | deine E-Mail für Let's Encrypt |
| `TRAEFIK_DASHBOARD_AUTH` | Ausgabe aus Schritt 4, **ohne** Anführungszeichen |
| `POSTGRES_DB` | wie lokal |
| `POSTGRES_USER` | wie lokal |
| `POSTGRES_PASSWORD` | neues, starkes Passwort |
| `JWT_ISSUER` | wie lokal |
| `JWT_SECRET` | neues, langes Secret |
| `JWT_EXPIRATION_MILLIS` | wie lokal |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | `update` (mit `create` wird die DB bei jedem Neustart geleert) |

Alternativ geht das mit der GitHub CLI im Projektordner:

```powershell
gh secret set SSH_HOST --body "164.90.12.34"
gh secret set SSH_USER --body "deploy"
Get-Content $HOME\.ssh\do_deploy -Raw | gh secret set SSH_PRIVATE_KEY
gh secret set DOMAIN --body "164-90-12-34.sslip.io"
gh secret set TRAEFIK_DASHBOARD_AUTH --body 'admin:$2y$05$....'
# ... und so weiter für die übrigen Secrets
```

In den Passwörtern für Postgres und JWT keine `$`, `'` oder `"` verwenden, damit die `.env` sauber gelesen wird.

## Schritt 6: Pushen und Deployment beobachten

```powershell
git add .github/workflows/deploy.yml docker-compose.yml docs/DEPLOYMENT.md
git commit -m "Aufgabe 5: Deployment auf DigitalOcean via GitHub Actions"
git push origin main
```

Im Tab **Actions** des Repositories laufen danach `build` und `deploy`. Der Workflow lässt sich dort auch manuell mit **Run workflow** starten.

## Schritt 7: Testen

```powershell
curl.exe -I http://164-90-12-34.sslip.io/api        # 301/308 Redirect auf https
curl.exe https://164-90-12-34.sslip.io/api/...       # Endpunkt aus der Postman-Collection
```

- Backend: `https://<DOMAIN>/api/...`
- Dashboard: `https://traefik.<DOMAIN>`. Der Browser fragt nach Benutzer und Passwort.
- Logs auf dem Droplet: `ssh -i $HOME\.ssh\do_deploy deploy@<IP>`, dann `cd /opt/user_mgmt_service && docker compose logs -f`

Das erste Zertifikat kann ein bis zwei Minuten dauern. Bis dahin zeigt der Browser eine Zertifikatswarnung (Traefik-Standardzertifikat).

## Variante ohne TLS (nur falls Let's Encrypt nicht möglich ist)

Die Aufgabe erlaubt HTTP, wenn keine Domain vorhanden ist. Mit sslip.io ist das in der Regel nicht nötig. Falls doch, in `docker-compose.yml`:

- die zwei Zeilen `--entrypoints.web.http.redirections...` entfernen
- bei beiden Routern `entrypoints=websecure` durch `entrypoints=web` ersetzen und die Zeilen `tls=true` und `tls.certresolver` entfernen

BasicAuth über HTTP überträgt das Passwort nur Base64-kodiert. Das sollte in der Dokumentation erwähnt werden.

## Akzeptanzkriterien

| Kriterium | Umsetzung |
|---|---|
| Deployment auf DigitalOcean Droplet | Ubuntu-Droplet mit Docker, Verzeichnis `/opt/user_mgmt_service` |
| Automatisch bei Push auf `main` | `on: push: branches: [main]` in `deploy.yml` |
| Docker Compose via SSH | `appleboy/scp-action` kopiert die Dateien, `appleboy/ssh-action` führt `docker compose up -d` aus |
| Secrets über GitHub Secrets | `.env` wird im Workflow aus `secrets.*` erzeugt; nichts Geheimes liegt im Repository |
| Öffentlich erreichbar | `https://<DOMAIN>/api` über Traefik mit Let's-Encrypt-Zertifikat |
| (Zusatz) Dashboard abgesichert | kein `api.insecure`, kein offener Port 8080/8081, nur HTTPS mit BasicAuth |
