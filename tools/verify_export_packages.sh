#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-godot}"
output_root="${1:-${RUNNER_TEMP:-/tmp}/neofutbol-export-verification}"
public_preset="Linux-Public"
development_preset="Linux-Development"
public_zip="$output_root/NEOFutbol-public.zip"
development_zip="$output_root/NEOFutbol-development.zip"

required_historical=(
  data/seasons/1982-83/clubs.json
  data/seasons/1982-83/manifest.json
  data/seasons/1982-83/players.json
  data/seasons/1982-83/rules.json
)
required_development=(
  data/dev/seasons/1982-83/clubs.json
  data/dev/seasons/1982-83/fixtures.json
  data/dev/seasons/1982-83/manifest.json
  data/dev/seasons/1982-83/players.json
  data/dev/seasons/1982-83/rules.json
)

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

reject_errors() {
  local log_file="$1"
  if grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$log_file"; then
    cat "$log_file" >&2
    fail "Godot informó errores; consulte $log_file"
  fi
}

run_logged() {
  local log_file="$1"
  shift
  local status
  set +e
  "$@" >"$log_file" 2>&1
  status=$?
  set -e
  if (( status != 0 )); then
    cat "$log_file" >&2
    fail "El comando terminó con código $status; consulte $log_file"
  fi
  reject_errors "$log_file"
}

export_zip() {
  local preset="$1"
  local archive="$2"
  local log_file="$3"
  run_logged "$log_file" "$godot_bin" --headless --path "$project_root" \
    --export-pack "$preset" "$archive"
  [[ -s "$archive" ]] || fail "No se generó el paquete $archive"
  unzip -tq "$archive" >/dev/null || fail "El ZIP $archive no es íntegro"
}

archive_listing() {
  local archive="$1"
  local destination="$2"
  unzip -Z1 "$archive" | LC_ALL=C sort -u >"$destination"
}

require_entry() {
  local listing="$1"
  local entry="$2"
  grep -Fqx -- "$entry" "$listing" \
    || fail "Falta $entry en $(basename "$listing" .list)"
}

reject_prefix() {
  local listing="$1"
  local prefix="$2"
  if grep -Fq -- "$prefix" "$listing"; then
    grep -F -- "$prefix" "$listing" >&2
    fail "El paquete $(basename "$listing" .list) contiene $prefix"
  fi
}

run_exported() {
  local label="$1"
  local executable="$2"
  shift 2
  local log_file="$output_root/$label.log"
  run_logged "$log_file" "$executable" --headless --quit-after 30 "$@"
}

rm -rf "$output_root"
mkdir -p "$output_root"

version="$($godot_bin --version)"
printf 'Godot: %s\n' "$version"
[[ "$version" == 4.7.2.stable.* && "$version" != *mono* ]] \
  || fail "Se requiere Godot 4.7.2 estándar"

export_zip "$public_preset" "$public_zip" "$output_root/public-export.log"
export_zip "$development_preset" "$development_zip" \
  "$output_root/development-export.log"

public_list="$output_root/public.list"
development_list="$output_root/development.list"
archive_listing "$public_zip" "$public_list"
archive_listing "$development_zip" "$development_list"

require_entry "$public_list" project.binary
require_entry "$development_list" project.binary
require_entry "$public_list" game/scripts/ui/main_menu.gd.remap
require_entry "$development_list" game/scripts/ui/main_menu.gd.remap

# Comprueba todos los JSON históricos que realmente existen en el repositorio.
mapfile -d '' -t source_historical < <(
  find "$project_root/data/seasons" -type f -name '*.json' -printf '%P\0' \
    | LC_ALL=C sort -z
)
(( ${#source_historical[@]} > 0 )) || fail "No hay JSON históricos de origen"
for relative_path in "${source_historical[@]}"; do
  require_entry "$public_list" "data/seasons/$relative_path"
  require_entry "$development_list" "data/seasons/$relative_path"
done
for entry in "${required_historical[@]}"; do
  require_entry "$public_list" "$entry"
  require_entry "$development_list" "$entry"
done
for entry in "${required_development[@]}"; do
  require_entry "$development_list" "$entry"
done

reject_prefix "$public_list" 'data/dev/'
reject_prefix "$public_list" 'tests/'
reject_prefix "$public_list" 'tools/'
reject_prefix "$development_list" 'tests/'
reject_prefix "$development_list" 'tools/'

if [[ "${VERIFY_RELEASE_BINARIES:-0}" == "1" ]]; then
  public_dir="$output_root/public"
  development_dir="$output_root/development"
  mkdir -p "$public_dir" "$development_dir"
  public_binary="$public_dir/NEOFutbol.x86_64"
  development_binary="$development_dir/NEOFutbol-dev.x86_64"
  run_logged "$output_root/public-release.log" \
    "$godot_bin" --headless --path "$project_root" --export-release \
    "$public_preset" "$public_binary"
  run_logged "$output_root/development-release.log" \
    "$godot_bin" --headless --path "$project_root" --export-release \
    "$development_preset" "$development_binary"
  [[ -x "$public_binary" && -s "$public_dir/NEOFutbol.pck" ]] \
    || fail "La exportación pública no produjo ejecutable y PCK"
  [[ -x "$development_binary" && -s "$development_dir/NEOFutbol-dev.pck" ]] \
    || fail "La exportación de desarrollo no produjo ejecutable y PCK"
  run_exported public-normal "$public_binary"
  run_exported public-rejects-development "$public_binary" -- --dev-season-pack
  run_exported development-normal "$development_binary"
  run_exported development-enabled "$development_binary" -- --dev-season-pack
fi

sha256sum "$public_zip" "$development_zip"
printf 'PASS: exportaciones %s y %s verificadas\n' \
  "$public_preset" "$development_preset"
