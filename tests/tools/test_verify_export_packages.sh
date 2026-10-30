#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verifier="$project_root/tools/verify_export_packages.sh"
test_root="$(mktemp -d)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  find "$test_root" -depth -delete
}
trap cleanup EXIT

run_verifier() {
  local parent="$1"
  local output artifacts expected_parent
  output="$("$verifier" "$parent")"
  printf '%s\n' "$output" >&2
  artifacts="$(sed -n 's/^Artefactos: //p' <<<"$output" | tail -n 1)"
  [[ -n "$artifacts" && -d "$artifacts" && ! -L "$artifacts" ]] \
    || fail "la ejecución no comunicó un directorio de artefactos válido"
  expected_parent="$(realpath --canonicalize-existing -- "$parent")"
  [[ "$(dirname -- "$artifacts")" == "$expected_parent" ]] \
    || fail "los artefactos no quedaron bajo el directorio solicitado"
  printf '%s\n' "$artifacts"
}

output_parent="$test_root/output"
mkdir -p "$output_parent"
sentinel="$output_parent/preexisting.txt"
printf 'contenido que debe conservarse\n' >"$sentinel"
sentinel_before="$(sha256sum "$sentinel")"
first_artifacts="$(run_verifier "$output_parent")"
[[ -f "$sentinel" && "$(sha256sum "$sentinel")" == "$sentinel_before" ]] \
  || fail "el archivo preexistente fue eliminado o modificado"
[[ "$first_artifacts" != "$output_parent" ]] \
  || fail "los artefactos no usan un subdirectorio exclusivo"

symlink_target="$test_root/symlink-target"
symlink_path="$test_root/symlink-output"
mkdir -p "$symlink_target"
printf 'intacto\n' >"$symlink_target/preexisting.txt"
ln -s "$symlink_target" "$symlink_path"
for unsafe_path in "$symlink_path" "$symlink_path/nested"; do
  if "$verifier" "$unsafe_path" >"$test_root/symlink.log" 2>&1; then
    fail "se aceptó una ruta de salida que atraviesa un enlace simbólico"
  fi
done
[[ "$(cat "$symlink_target/preexisting.txt")" == "intacto" ]] \
  || fail "el destino del enlace simbólico fue modificado"
[[ "$(find "$symlink_target" -mindepth 1 -maxdepth 1 | wc -l)" == "1" ]] \
  || fail "se escribieron artefactos a través del enlace simbólico"

tracked_before="$test_root/tracked-before.sha256"
tracked_after="$test_root/tracked-after.sha256"
(
  cd "$project_root"
  git ls-files -z | LC_ALL=C sort -z | xargs -0 sha256sum
) >"$tracked_before"
repo_artifacts="$(run_verifier "$project_root")"
case "$repo_artifacts" in
  "$project_root"/neofutbol-export-verification.*) ;;
  *) fail "la ejecución en la raíz produjo una ruta inesperada" ;;
esac
(
  cd "$project_root"
  git ls-files -z | LC_ALL=C sort -z | xargs -0 sha256sum
) >"$tracked_after"
cmp -s "$tracked_before" "$tracked_after" \
  || fail "la ejecución en la raíz modificó archivos versionados"

# Solo se elimina el subdirectorio exclusivo recién creado y ya validado.
find "$repo_artifacts" -depth -delete
printf 'PASS: archivos preexistentes y raíz del repositorio preservados\n'
