# Verschlüsselte ToDos

ToDo-App für **Windows** und **Android** (Flutter), die ein **privates
GitHub-Repository als Datenbank** nutzt. Jedes ToDo ist ein einzelnes, mit
**AES-256-GCM** verschlüsseltes Dokument; der Schlüssel wird per **Argon2id**
aus einer Passphrase abgeleitet. GitHub sieht ausschließlich Ciphertext
(Zero-Knowledge).

## Funktionen

- Offline-First: erstellen, ändern, löschen ohne Netz; Sync-Queue spielt
  Änderungen später gegen GitHub ab (Contents API, kein Git nötig)
- Konfliktstrategie „Last write wins" mit Konfliktkopien — nichts geht verloren
- Listenansicht mit Suche, Status-/Tag-Filtern und Fälligkeits-Gruppierung
- Kalenderansicht (Monatsraster + Tagesagenda, Überfällig-Hervorhebung)
- Felder nach RFC-5545-Vorbild: Status, Priorität, Fälligkeit, Start, Tags,
  Liste, Teilschritte, Wiederholungen, Erinnerungen
- Erinnerungen als Android-Benachrichtigungen (exakte Alarme, reboot-fest)
- Zugangsdaten/Schlüssel sicher lokal: Windows DPAPI bzw. Android Keystore

## Architektur

```
lib/src/
  models/         Todo-Datenmodell + Wiederholungslogik
  crypto/         Argon2id-KDF + AES-256-GCM-Dokumentformat
  storage/        lokaler verschlüsselter Store + Sync-Queue
  sync/           GitHub-Contents-API-Client + Sync (LWW, index.enc)
  notifications/  Erinnerungen (flutter_local_notifications)
  settings/       sichere Konfigurationsablage
  ui/             Onboarding, Liste, Editor, Kalender, Einstellungen
```

Layout des Daten-Repos (separates, privates Repository):

```
todos/<uuid>.enc   ein verschlüsseltes JSON-Dokument pro ToDo
index.enc          verschlüsselter Index (schneller Bootstrap)
meta.json          KDF-Parameter (Salt etc.), unverschlüsselt
```

## Entwicklung (Container)

Alles Nötige (Flutter, Android SDK, JDK) steckt im [Containerfile](Containerfile):

```sh
podman build -t todo-dev -f Containerfile .
podman run -d --name todo-dev -v <projektordner>:/work localhost/todo-dev
podman exec todo-dev bash -c "cd /work/encrypted-todo-app && flutter test"
```

Der Windows-Desktop-Build benötigt MSVC und läuft daher nicht im Container,
sondern in der CI (`windows-latest`) bzw. lokal mit Visual Studio.

## Release & Verteilung

Ein Git-Tag `v*` (z. B. `v0.1.0`) stößt [release.yml](.github/workflows/release.yml) an:

1. **Windows-ZIP** → als Asset an das GitHub-Release angehängt
2. **signierte APK** → ebenfalls Release-Asset
3. **F-Droid-Updatesite** → Branch `gh-pages`, ausgeliefert über GitHub Pages

Benötigte Actions-Secrets (einmalig unter *Settings → Secrets and variables →
Actions* eintragen):

| Secret | Inhalt |
|---|---|
| `KEYSTORE_P12_BASE64` | PKCS12-Keystore, Base64-kodiert (Alias `release`) |
| `KEYSTORE_PASSWORD` | Passwort des Keystores |

Der Keystore signiert APK **und** F-Droid-Index. Er darf nie ins Repo und
nicht verloren gehen — ohne ihn sind keine Updates der installierten App
möglich.

### F-Droid-Paketquelle einbinden

Im F-Droid-Client: *Einstellungen → Paketquellen → +* und die URL von der
GitHub-Pages-Startseite übernehmen (inkl. `?fingerprint=…`):

```
https://sebastianweber.github.io/encrypted-todo-app/repo?fingerprint=<FINGERPRINT>
```

GitHub Pages muss einmalig aktiviert werden (*Settings → Pages → Branch:
gh-pages*), nachdem der erste Release-Lauf den Branch erzeugt hat.

## Einrichtung der App

Beim ersten Start fragt die App ab:

1. **GitHub:** Besitzer, Repository (das private Daten-Repo), Branch und ein
   *fine-grained Personal Access Token* mit Lese-/Schreibrecht **nur auf
   „Contents" dieses einen Repos** (github.com → Settings → Developer settings
   → Fine-grained tokens).
2. **Passphrase:** verschlüsselt alle Daten. **Kein Recovery möglich** —
   sicher aufbewahren. Weitere Geräte: gleiche Passphrase eingeben.
