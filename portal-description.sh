#!/usr/bin/env bash
# Generate mod-portal-description.md: README.md with the screenshots listed in
# portal-images.txt inserted after their anchor lines. The mod portal cannot
# use images from the repo, so the README is kept image-free and the portal
# text is derived from it. Paste the output into the Description field at
# https://mods.factorio.com/mod/logistics-insights/edit
#
# Fails if an anchor in portal-images.txt matches no README line, so a README
# edit cannot silently drop a screenshot.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readme="$root/README.md"
images="$root/portal-images.txt"
out="$root/mod-portal-description.md"
trap 'rm -f "$out.tmp"' EXIT

awk -v images="$images" '
BEGIN {
  n = 0
  while ((getline line < images) > 0) {
    if (line ~ /^[[:space:]]*(#|$)/) continue
    sep = index(line, " | ")
    if (sep == 0) { printf "portal-images.txt: no \" | \" in: %s\n", line > "/dev/stderr"; bad = 1; continue }
    anchor[++n] = substr(line, 1, sep - 1)
    image[n] = substr(line, sep + 3)
    used[n] = 0
  }
  close(images)
}
{
  print
  for (i = 1; i <= n; i++)
    if (index($0, anchor[i]) == 1) { print image[i]; used[i]++ }
}
END {
  for (i = 1; i <= n; i++)
    if (used[i] != 1) { printf "portal-images.txt: anchor matched %d lines (want 1): %s\n", used[i], anchor[i] > "/dev/stderr"; bad = 1 }
  if (bad) exit 1
}
' "$readme" > "$out.tmp"

mv "$out.tmp" "$out"
echo "$out  ($(grep -c '^!\[' "$out") images)"
