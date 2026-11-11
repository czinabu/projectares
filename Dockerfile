# Dedicated server image for Project Ares.
#
# Build:  docker build -t ares-server .
# Run:    docker run -d -t --init --name ares -p 24565-24569:24565-24569/udp -v ares-data:/data ares-server
#
# The first build downloads Godot and its export templates (about 1.3 GB), so it
# takes a few minutes. Later builds reuse that step and only re-export the game.
# See docs/hosting.md for the full walkthrough.

ARG GODOT_VERSION=4.7

# ---- Stage 1: export the game with the "Linux Server" preset ----------------
FROM debian:bookworm-slim AS build
ARG GODOT_VERSION
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip \
	&& rm -rf /var/lib/apt/lists/*

# Godot itself, plus only the one export template the server needs.
RUN set -eux; \
	base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"; \
	curl -fsSL -o /tmp/godot.zip "${base}/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"; \
	unzip -q /tmp/godot.zip -d /tmp; \
	mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot; \
	curl -fsSL -o /tmp/templates.tpz "${base}/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"; \
	dest="/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable"; \
	mkdir -p "$dest"; \
	unzip -q -j /tmp/templates.tpz templates/linux_release.x86_64 templates/version.txt -d "$dest"; \
	rm -f /tmp/godot.zip /tmp/templates.tpz

WORKDIR /src
COPY . .
RUN godot --headless --path . --import \
	&& mkdir -p build/server \
	&& godot --headless --path . --export-release "Linux Server" build/server/ares_server.x86_64 \
	&& test -x build/server/ares_server.x86_64

# ---- Stage 2: a small image that only runs the server -----------------------
FROM debian:bookworm-slim
RUN useradd --create-home --shell /usr/sbin/nologin ares \
	&& mkdir -p /data/accounts && chown -R ares:ares /data
COPY --from=build /src/build/server/ares_server.x86_64 /app/ares_server
USER ares
WORKDIR /home/ares
# The plaza and raid worlds, and the arena ten ports above the plaza.
EXPOSE 24565-24569/udp 24575/udp
# Player stashes are saved here. Keep it on a volume so they survive updates.
VOLUME /data
# Everything after "--" goes to the game. Override CMD to change the world,
# port, bot count or squad spawns, for example:
#   docker run ... ares-server --server --world frostline --bots 4 --accounts /data/accounts
ENTRYPOINT ["/app/ares_server", "--headless", "--"]
CMD ["--server", "--world", "ashfront", "--port", "24565", "--accounts", "/data/accounts"]
