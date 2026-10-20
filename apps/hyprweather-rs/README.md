# Dashboard weather

Small on-demand Rust helper; QML owns the dashboard card. No daemon, polling,
async runtime or extra window. HTTPS uses the system `curl` executable (bounded
connection/total time, HTTPS only, response size limit, no shell). Rust owns
validation, JSON, location selection, cache freshness and atomic persistence.

Build with `cargo build --release --locked --manifest-path apps/hyprweather-rs/Cargo.toml`.
Install the release binary at `~/.config/quickshell/helpers/hyprweather`.
The Hyprshell installer builds and stages it transactionally. `curl` is included
in both package manifests. Binary and build outputs are excluded from Git/sync.

On each dashboard opening the helper emits cached JSON immediately, then fetches
only if older than 15 minutes. It exits after the request. No automatic retries
or scheduled network work while closed; an in-flight request may finish after closing. Search and explicit location changes are
user-triggered. Failed requests retain stale weather with an error and timestamp.

`search NAME [COUNTRY]` uses Open-Meteo geocoding; COUNTRY defaults to PH and an
empty string enables worldwide results. Province/region names distinguish
municipalities. GeoNames coverage varies; manual named coordinates support
locations missing from the index. `select LOCATION_JSON` saves a validated place.
No automatic IP/GPS location lookup. `weather` prints newline-delimited snapshots.

Preferences: `$XDG_CONFIG_HOME/hyprshell/weather.json` (default `~/.config`).
Cache: `$XDG_STATE_HOME/hyprshell/weather/` (default `~/.local/state`).
The selected city follows existing preference preservation and Sync to GitHub;
the disposable cache stays local. No city is selected by default.

Weather is modeled data, not a local station reading or an official warning feed.
Current rain is the preceding 15-minute amount; rain chance is today's maximum.
Sun times use the selected location's time zone. Source attribution appears on
the card. APIs: https://open-meteo.com/en/docs and
https://open-meteo.com/en/docs/geocoding-api (location data: GeoNames).

Validation: `cargo test`, `cargo clippy --all-targets -- -D warnings`, and
`python3 -m unittest discover -s tests -p test_weather.py -v` after installing a
build at the checkout's `config/quickshell/helpers/hyprweather`. Tests isolate
XDG roots and substitute only HTTPS responses, exercising the real Rust CLI and
native QML picker, caching, stale offline recovery and absence of polling.
