#!/usr/bin/env bash
# Build the release zips for Logistics Insights.
#
# Factorio loads a mod only when its info.json "factorio_version" matches the
# running game's major.minor, and the field takes exactly one value. The code
# runs unchanged on 2.0 and 2.1, so one source tree is shipped as two zips.
# The mod portal refuses a second release with an existing version number, so
# the two builds are two version lines: the minor tracks the game version and
# the patch is shared.
#
#   dist/2.1/<name>_1.<m>.<p>.zip     factorio_version "2.1", version as in git
#   dist/2.0/<name>_1.<m-1>.<p>.zip   factorio_version "2.0"
#
# The base and flib dependency bounds also differ per game version: flib 0.17+
# is built for 2.1 only and 0.15/0.16 for 2.0 only, so each zip gets the
# floors that exist for its game. The tree in git carries the 2.1 bounds.
#
# So with 1.3.4 in git the 2.0 build is 1.2.4. Upload both to the mod portal;
# each player's game is offered the release for its own version. New
# migrations are keyed by the 2.0 line; see the comment above the table in
# scripts/migrations.lua.
#
# Also regenerates mod-portal-description.md (see portal-description.sh), the
# README with screenshots for pasting into the mod portal's Description field.
#
# Requires jq, rsync and zip. Files listed in info.json "package.ignore" are
# left out, as are top-level dotfiles, dist/, zips and this script.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
info="$root/info.json"
dist="$root/dist"

name="$(jq -r .name "$info")"
version="$(jq -r .version "$info")"
game_version="$(jq -r .factorio_version "$info")"

if [[ "$game_version" != "2.1" ]]; then
  echo "info.json factorio_version is \"$game_version\"; this script expects the tree to target 2.1" >&2
  exit 1
fi

IFS=. read -r major minor patch <<< "$version"
if [[ -z "${patch:-}" || ! "$minor" =~ ^[0-9]+$ ]]; then
  echo "info.json version \"$version\" is not major.minor.patch" >&2
  exit 1
fi

if (( minor < 3 )); then
  echo "info.json version is $version; the 2.1 line starts at 1.3.0 (the 2.0 line is one minor below)" >&2
  exit 1
fi
version_20="$major.$((minor - 1)).$patch"

# rsync exclude list: package.ignore patterns plus build noise. A "dir/**"
# pattern would leave the directory itself behind as an empty folder, so it is
# trimmed to "dir". Top-level dotfiles (.busted, .lua-format, .vscode, .git,
# .gitignore) are tooling, not mod content.
excludes=()
while IFS= read -r pattern; do
  excludes+=(--exclude "${pattern%/\*\*}")
done < <(jq -r '.package.ignore[]' "$info")
excludes+=(--exclude '/.*' --exclude dist --exclude '*.zip' --exclude build.sh)

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# Dependency floors per game version. The tree's info.json holds the 2.1 ones;
# check them so a drift there is caught rather than silently shipped.
deps_21='["base >= 2.1.0", "flib >= 0.17.0"]'
deps_20='["base >= 2.0.55", "flib >= 0.15.0"]'
if ! jq -e --argjson want "$deps_21" '
      [.dependencies[] | select(test("^(base|flib) "))] == $want' "$info" > /dev/null; then
  echo "info.json base/flib dependencies are not the expected 2.1 bounds $deps_21" >&2
  exit 1
fi

# Factorio requires the zip to contain a single top-level folder named
# <name>_<version>, matching the version in info.json.
build_zip() {
  local ver="$1" game="$2" deps="$3"
  local folder="${name}_${ver}"
  local out="$dist/$game"
  rm -rf "$stage/$folder"
  rsync -a "${excludes[@]}" "$root/" "$stage/$folder/"
  # Replace the base and flib entries in place; optional dependencies are kept.
  jq --arg v "$ver" --arg g "$game" --argjson deps "$deps" '
      .version = $v | .factorio_version = $g
      | .dependencies |= map(
          if test("^base ") then $deps[0]
          elif test("^flib ") then $deps[1]
          else . end)' "$info" > "$stage/$folder/info.json"
  mkdir -p "$out"
  rm -f "$out/$folder.zip"
  (cd "$stage" && zip -qr "$out/$folder.zip" "$folder")
  echo "$out/$folder.zip  (factorio_version $game, version $ver)"
}

"$root/portal-description.sh"
build_zip "$version" "2.1" "$deps_21"
build_zip "$version_20" "2.0" "$deps_20"
