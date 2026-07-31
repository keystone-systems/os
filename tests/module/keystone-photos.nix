{
  pkgs,
  lib,
  ks ? pkgs.keystone.ks,
}:
pkgs.runCommand "keystone-photos-check"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      jq
      python3
      util-linux
    ];
  }
  ''
        export PATH="${
          pkgs.lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.gnused
            pkgs.jq
            pkgs.python3
            pkgs.util-linux
          ]
        }"

        cd ${../..}
        KS_BIN="${ks}/bin/ks"
        TMP_DIR="$(mktemp -d)"
        IMMICH_URL="http://127.0.0.1:18080"
        SERVER_PID=""

        cleanup() {
          local exit_code=$?
          if [[ -n "$SERVER_PID" ]]; then
            kill "$SERVER_PID" >/dev/null 2>&1 || true
            wait "$SERVER_PID" >/dev/null 2>&1 || true
          fi
          rm -rf "$TMP_DIR"
          exit "$exit_code"
        }
        trap cleanup EXIT INT TERM

        assert_status() {
          local name="$1"
          local expected="$2"
          local actual
          actual="$(cat "$TMP_DIR/$name.status")"

          if [[ "$actual" != "$expected" ]]; then
            echo "FAIL: $name exited with $actual, expected $expected" >&2
            echo "--- stdout ---" >&2
            cat "$TMP_DIR/$name.out" >&2 || true
            echo "--- stderr ---" >&2
            cat "$TMP_DIR/$name.err" >&2 || true
            exit 1
          fi
        }

        assert_contains() {
          local name="$1"
          local pattern="$2"
          local combined="$TMP_DIR/$name.combined"

          cat "$TMP_DIR/$name.out" "$TMP_DIR/$name.err" >"$combined"
          if ! grep -Fq -- "$pattern" "$combined"; then
            echo "FAIL: $name missing pattern: $pattern" >&2
            echo "--- combined output ---" >&2
            cat "$combined" >&2 || true
            exit 1
          fi
        }

        run_capture() {
          local name="$1"
          shift

          local stdout_file="$TMP_DIR/$name.out"
          local stderr_file="$TMP_DIR/$name.err"
          local status_file="$TMP_DIR/$name.status"

          if "$@" >"$stdout_file" 2>"$stderr_file"; then
            printf '0\n' >"$status_file"
          else
            printf '%s\n' "$?" >"$status_file"
          fi
        }

        create_fake_server() {
          cat >"$TMP_DIR/immich-server.py" <<'PY'
    import json
    import os
    import pathlib
    import re
    import sys
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    tmp_dir = pathlib.Path(sys.argv[1])
    port = int(sys.argv[2])

    def write_text(path: pathlib.Path, value: str) -> None:
        path.write_text(value, encoding="utf-8")

    def append_text(path: pathlib.Path, value: str) -> None:
        with path.open("a", encoding="utf-8") as handle:
            handle.write(value)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            return

        def _body(self) -> bytes:
            length = int(self.headers.get("Content-Length", "0"))
            return self.rfile.read(length) if length > 0 else b""

        def _json(self, payload, status=200):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _bytes(self, payload: bytes, content_type: str):
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            if self.path == "/api/people":
                self._json([
                    {"id": "person-1", "name": "Nick Romero", "isFavorite": True},
                    {"id": "person-2", "name": "Someone Else", "isFavorite": False},
                ])
                return
            if self.path == "/api/tags":
                self._json([
                    {"id": "tag-1", "name": "receipt", "value": "receipt"},
                    {"id": "tag-2", "name": "family", "value": "family"},
                ])
                return
            if self.path == "/api/assets/asset-1":
                self._json({
                    "id": "asset-1",
                    "originalFileName": "nick-romero-card.jpg",
                    "originalPath": "/photos/cards/nick-romero-card.jpg",
                    "type": "IMAGE",
                })
                return
            if self.path == "/api/assets/asset-1/original":
                self._bytes(b"fake-binary-data\n", "application/octet-stream")
                return
            if self.path == "/api/albums":
                albums = [{"id": "album-1", "albumName": "Screenshots - testuser"}]
                if (tmp_dir / "album-created").exists():
                    albums.append({"id": "album-2", "albumName": "New Screenshots - testuser"})
                self._json(albums)
                return

            self.send_error(404, "unknown path")

        def do_POST(self):
            body = self._body()
            if self.path in {"/api/search/smart", "/api/search/metadata"}:
                write_text((tmp_dir / "request.json"), body.decode("utf-8"))
                if self.path == "/api/search/smart":
                    self._json({
                        "assets": {
                            "items": [
                                {
                                    "id": "asset-1",
                                    "originalFileName": "nick-romero-card.jpg",
                                    "originalPath": "/photos/cards/nick-romero-card.jpg",
                                    "type": "IMAGE",
                                    "fileCreatedAt": "2026-03-01T12:00:00.000Z",
                                    "exifInfo": {
                                        "dateTimeOriginal": "2026-03-01T12:00:00.000Z",
                                        "description": "Nick Romero business card",
                                        "city": "Austin",
                                        "state": "Texas",
                                        "country": "United States",
                                        "make": "Apple",
                                        "model": "iPhone 15 Pro",
                                        "lensModel": "Main Camera",
                                    },
                                    "people": [{"name": "Nick Romero"}],
                                    "tags": [{"name": "receipt", "value": "receipt"}],
                                }
                            ]
                        }
                    })
                else:
                    self._json({
                        "assets": {
                            "items": [
                                {
                                    "id": "asset-2",
                                    "originalFileName": "IMG_2048.jpg",
                                    "originalPath": "/photos/trips/IMG_2048.jpg",
                                    "type": "IMAGE",
                                    "fileCreatedAt": "2026-02-01T12:00:00.000Z",
                                    "exifInfo": {
                                        "dateTimeOriginal": "2026-02-01T12:00:00.000Z",
                                        "description": "Family receipt in Austin",
                                        "city": "Austin",
                                        "state": "Texas",
                                        "country": "United States",
                                        "make": "Apple",
                                        "model": "iPhone 15 Pro",
                                        "lensModel": "Main Camera",
                                    },
                                    "people": [{"name": "Nick Romero"}, {"name": "Someone Else"}],
                                    "tags": [
                                        {"name": "receipt", "value": "receipt"},
                                        {"name": "family", "value": "family"},
                                    ],
                                }
                            ]
                        }
                    })
                return
            if self.path == "/api/albums":
                (tmp_dir / "album-created").touch()
                append_text((tmp_dir / "sync-events.log"), "create-album\n")
                self._json({"id": "album-2", "albumName": "New Screenshots - testuser"})
                return
            if self.path == "/api/assets":
                text = body.decode("utf-8", errors="ignore")
                match = re.search(r'filename="([^"]+)"', text)
                if match:
                    append_text((tmp_dir / "sync-events.log"), f"upload {os.path.basename(match.group(1))}\n")
                self._json({"id": "uploaded-asset-1", "status": "created"})
                return
            if self.path in {"/api/albums/album-1/assets", "/api/albums/album-2/assets"}:
                append_text((tmp_dir / "sync-events.log"), "album-add\n")
                self._json({})
                return
            if self.path == "/api/tags/upsert":
                append_text((tmp_dir / "sync-events.log"), "tag-upsert\n")
                write_text((tmp_dir / "tag-upsert-request.json"), body.decode("utf-8"))
                self._json([
                    {"id": "tag-source", "value": "source:screenshot"},
                    {"id": "tag-host", "value": "host:test-host"},
                    {"id": "tag-account", "value": "account:testuser"},
                ])
                return
            if self.path in {
                "/api/tags/tag-source/assets",
                "/api/tags/tag-host/assets",
                "/api/tags/tag-account/assets",
            }:
                append_text((tmp_dir / "sync-events.log"), "tag-asset\n")
                self._json({})
                return

            self.send_error(404, "unknown path")

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    write_text((tmp_dir / "server-ready"), "ready\n")
    server.serve_forever()
    PY

          ${pkgs.python3}/bin/python3 "$TMP_DIR/immich-server.py" "$TMP_DIR" 18080 >"$TMP_DIR/server.log" 2>&1 &
          SERVER_PID=$!

          for _ in $(seq 1 50); do
            [[ -f "$TMP_DIR/server-ready" ]] && return 0
            sleep 0.1
          done

          echo "FAIL: fake Immich server did not start" >&2
          cat "$TMP_DIR/server.log" >&2 || true
          exit 1
        }

        create_fake_server

        run_capture help env "$KS_BIN" photos --help
        assert_status help 0
        assert_contains help "Usage: ks photos"
        assert_contains help "search"
        assert_contains help "people"

        run_capture screenshots-help env "$KS_BIN" screenshots --help
        assert_status screenshots-help 0
        assert_contains screenshots-help "Usage: ks screenshots"
        assert_contains screenshots-help "sync"

        run_capture missing-creds env "$KS_BIN" photos search --text acme
        assert_status missing-creds 1
        assert_contains missing-creds "missing Immich URL"

        run_capture json-search env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          "$KS_BIN" photos search --text "Nick Romero" --kind business-card --json
        assert_status json-search 0
        assert_contains json-search '"filename": "nick-romero-card.jpg"'
        assert_contains json-search '"kind": "business-card"'

        if ! grep -Fq 'business card' "$TMP_DIR/request.json"; then
          echo "FAIL: business-card request was not expanded" >&2
          cat "$TMP_DIR/request.json" >&2 || true
          exit 1
        fi

        run_capture person-search env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          "$KS_BIN" photos search --person "Nick Romero" --json
        assert_status person-search 0
        assert_contains person-search '"people": ['
        assert_contains person-search '"filename": "IMG_2048.jpg"'

        run_capture table-search env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          "$KS_BIN" photos search --text "Nick Romero"
        assert_status table-search 0
        assert_contains table-search 'nick-romero-card.jpg'
        assert_contains table-search 'MATCH'

        run_capture advanced-search env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          "$KS_BIN" photos search \
            --album "Screenshots - testuser" \
            --tag "receipt" \
            --country "United States" \
            --state "Texas" \
            --city "Austin" \
            --camera-make "Apple" \
            --camera-model "iPhone 15 Pro" \
            --lens-model "Main Camera" \
            --filename "IMG_" \
            --description "receipt" \
            --type image \
            --from 2026-02-01 \
            --to 2026-02-28 \
            --json
        assert_status advanced-search 0
        assert_contains advanced-search '"filename": "IMG_2048.jpg"'
        assert_contains advanced-search '"country": "United States"'
        assert_contains advanced-search '"make": "Apple"'

        if [[ "$(jq -r '.albumIds[0] // empty' "$TMP_DIR/request.json")" != "album-1" ]]; then
          echo "FAIL: advanced-search did not resolve album ids" >&2
          cat "$TMP_DIR/request.json" >&2 || true
          exit 1
        fi

        if [[ "$(jq -r '.tagIds[0] // empty' "$TMP_DIR/request.json")" != "tag-1" ]]; then
          echo "FAIL: advanced-search did not resolve tag ids" >&2
          cat "$TMP_DIR/request.json" >&2 || true
          exit 1
        fi

        run_capture people-list env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          "$KS_BIN" photos people --json
        assert_status people-list 0
        assert_contains people-list '"name": "Nick Romero"'

        run_capture download env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          XDG_CACHE_HOME="$TMP_DIR/cache" \
          "$KS_BIN" photos download asset-1 --print-path
        assert_status download 0

        downloaded_path="$(tr -d '\n' < "$TMP_DIR/download.out")"
        if [[ ! -f "$downloaded_path" ]]; then
          echo "FAIL: download did not create the target file" >&2
          exit 1
        fi

        if ! grep -Fq 'fake-binary-data' "$downloaded_path"; then
          echo "FAIL: download did not write the expected asset payload" >&2
          cat "$downloaded_path" >&2 || true
          exit 1
        fi

        mkdir -p "$TMP_DIR/screenshots" "$TMP_DIR/state"
        printf 'fake png\n' >"$TMP_DIR/screenshots/screenshot-1.png"

        run_capture sync-first env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          "$KS_BIN" screenshots sync \
            --directory "$TMP_DIR/screenshots" \
            --album-name "New Screenshots - testuser" \
            --host-name "test-host" \
            --account-name "testuser" \
            --state-file "$TMP_DIR/state/sync.tsv"
        assert_status sync-first 0

        if ! grep -Fq 'upload screenshot-1.png' "$TMP_DIR/sync-events.log"; then
          echo "FAIL: sync-first did not upload the screenshot" >&2
          cat "$TMP_DIR/sync-events.log" >&2 || true
          exit 1
        fi

        if ! grep -Fq 'create-album' "$TMP_DIR/sync-events.log"; then
          echo "FAIL: sync-first did not create the album" >&2
          cat "$TMP_DIR/sync-events.log" >&2 || true
          exit 1
        fi

        if ! grep -Fq 'account:testuser' "$TMP_DIR/tag-upsert-request.json"; then
          echo "FAIL: sync-first did not request account tag upsert" >&2
          cat "$TMP_DIR/tag-upsert-request.json" >&2 || true
          exit 1
        fi

        sync_event_count_before="$(wc -l < "$TMP_DIR/sync-events.log")"

        run_capture sync-second env \
          IMMICH_URL="$IMMICH_URL" \
          IMMICH_API_KEY="secret" \
          TMP_DIR="$TMP_DIR" \
          "$KS_BIN" screenshots sync \
            --directory "$TMP_DIR/screenshots" \
            --album-name "New Screenshots - testuser" \
            --host-name "test-host" \
            --account-name "testuser" \
            --state-file "$TMP_DIR/state/sync.tsv"
        assert_status sync-second 0

        sync_event_count_after="$(wc -l < "$TMP_DIR/sync-events.log")"
        if [[ "$sync_event_count_before" != "$sync_event_count_after" ]]; then
          echo "FAIL: sync-second should have skipped the already uploaded file" >&2
          cat "$TMP_DIR/sync-events.log" >&2 || true
          exit 1
        fi

        touch "$out"
  ''
