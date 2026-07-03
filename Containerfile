# Entwicklungs- und Build-Container für encrypted-todo-app
#
# Enthält Flutter SDK, Android SDK und JDK (Basis-Image von Cirrus Labs)
# sowie Werkzeuge für Signierung (openssl/keytool) und F-Droid-Index-Erzeugung.
#
# Bauen:   podman build -t todo-dev -f Containerfile .
# Starten: podman run -d --name todo-dev -v <repo-pfad>:/work localhost/todo-dev
# Nutzen:  podman exec todo-dev flutter test
#
# Der Windows-Desktop-Build (MSVC) ist in diesem Linux-Container nicht möglich
# und läuft in GitHub Actions auf windows-latest.

# 3.44.0 = neuestes verfügbares Cirrus-Labs-Tag; CI baut mit 3.44.4 (nur Patch-Differenz)
FROM ghcr.io/cirruslabs/flutter:3.44.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssl \
        zip \
        unzip \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Das Repo wird beim Start nach /work gemountet
WORKDIR /work

# Gemountetes Verzeichnis gehört dem Windows-Host — für git im Container freigeben
RUN git config --global --add safe.directory /work

# Dauerläufer: Entwicklung erfolgt über `podman exec`
ENTRYPOINT ["sleep", "infinity"]
