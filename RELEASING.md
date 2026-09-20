# Releasing Logistics Insights

A checklist for cutting a release. Every release ships twice from one source
tree: 1.3.x for Factorio 2.1 and 1.2.x for Factorio 2.0, with the same patch
number. Only the 2.1 version appears in git; `build.sh` derives the 2.0 one.

## 1. Before tagging

- [ ] Run the unit tests: `busted` (see [tests/TESTING.md](tests/TESTING.md)).
      Run the integration tests too if scanning, migrations or the scheduler changed.
- [ ] Any new migration in `scripts/migrations.lua` is keyed by the **2.0 line**
      (`"1.2.<p>"`, never `"1.3.<p>"`). See the comment above the table there.
- [ ] `changelog.txt`: the top block is `Version: 1.3.<p>` with today's date and
      lists every user-visible change. Factorio's changelog format is strict:
      `---` rule of exactly 99 dashes, `Version:` and `Date:` lines, then
      category headers indented two spaces and entries indented four.
- [ ] `info.json`: `version` is `1.3.<p>` and `factorio_version` is `"2.1"`.
- [ ] New settings, rows or suggestions are described in `README.md`. New
      locale strings are in `locale/en` (other languages arrive via Crowdin).
- [ ] If the README changed, decide whether any screenshot in
      `portal-images.txt` now shows something that no longer exists.

## 2. Build

```
./build.sh
```

This regenerates `mod-portal-description.md` (fails if `portal-images.txt`
has an anchor that no longer matches a README line) and writes:

- `dist/2.1/logistics-insights_1.3.<p>.zip`
- `dist/2.0/logistics-insights_1.2.<p>.zip`

Load the 2.1 zip in Factorio once: start a game and open the main window, and
load a save made with the previous version to run the migration.

## 3. Commit and tag

```
git add -A && git commit -m "Release 1.3.<p>"
git tag v1.3.<p>
git push && git push --tags
```

## 4. Upload to the mod portal

At https://mods.factorio.com/mod/logistics-insights/downloads/edit upload
**both** zips. The portal refuses a version number it has already seen, which
is why the two lines differ in the minor number. The in-game browser offers
each player the release matching their game version.

## 5. Update the portal description

The portal cannot show images from the repo, so `README.md` stays image-free
and `mod-portal-description.md` is the README with portal-hosted screenshots
inserted. Never edit the generated file.

1. New or replaced screenshots: upload them under Images on
   https://mods.factorio.com/mod/logistics-insights/edit and copy each
   `assets-mod.factorio.com` URL into `portal-images.txt`. A row is
   `<start of the README line it follows> | ![alt](url)`.
2. Regenerate with `./portal-description.sh` (build.sh does this too).
3. Paste the whole of `mod-portal-description.md` into the Description field
   and save. Check the public page shows every image.

The current portal text can be fetched exactly, as markdown, from
`https://mods.factorio.com/api/mods/logistics-insights/full` (field
`description`) to compare against the README before pasting.

## 6. Afterwards

- Bump `info.json` to the next patch and start a new `changelog.txt` block
  when work on the next release begins, not before.
- Keep an eye on the portal discussion page and GitHub issues for reports of
  migration problems in the first days.
