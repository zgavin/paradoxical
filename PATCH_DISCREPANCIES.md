# Patch discrepancies

A running log of oddities in Paradox's game versioning that we've hit
while identifying builds for the parse smoke and the regression
corpus (MODERNIZATION.md phase 1e). Paradox's wikis, forum posts,
SteamDB, and the game files themselves don't always agree. When they
don't, this is what we found and what we went with.

Builds are identified from the files themselves, never from labels:
`launcher-settings.json`'s `rawVersion` for most games, and the
`binaries/checksum.txt` suffix mapped through `BUILD_VERSION_MAP` for
EU5. SteamDB's manifest labels are the Steam branch a manifest was
seen on, not a version.

## Europa Universalis V

- **No 1.0.1.** The 1.0 launch build (checksum `e7e4`) went straight
  to 1.0.2. Neither the depot history nor the patch notes have a 1.0.1.
- **`e7e4` was mapped to 1.0.7 until #123.** That checksum is the 1.0
  launch build; 1.0.7 is `724a`.
- **1.1.0–1.1.8 open beta, all on Steam's `1.1.0` branch.** Steam
  doesn't allow renaming a branch, so every update in the beta stayed
  on it.
- **1.1.3's forum post repeats 1.1.2's checksum (`2675`).** It was
  presumably copied from the 1.1.2 post. 1.1.3 is `d568`, the only
  branch build between 1.1.2 and 1.1.4, two days after 1.1.2,
  matching the posting dates.
- **Obfuscated public checksums from 1.2.0 on.** The checksum shown in
  the launcher no longer matches the disk suffix, so 1.2.0+ map
  entries come from real installs or downloads. 1.3.6 had no official
  checksum at all (in-game value `872e`).
- **1.3.x open beta skipped every odd patch number.** 1.3.1, 1.3.3,
  1.3.5, 1.3.7, and 1.3.9 were reserved for hotfixes that never
  shipped. 1.3.10 was both the final beta build and the first official
  1.3.x release.
- **The 1.4.0 disk suffix is `d9c8`, not `9fc8`.** It was misread in
  #116, and #118 fixed it. A nil `installed_version` applies every
  correction, so the smoke passed anyway; the smoke now prints the
  detected version and the corpus asserts it.

## Stellaris

- **No 1.7.** 1.6.2 went straight to 1.8.
- **3.0.4 exists** (August 2021), but the wiki's patch list doesn't
  have it.
- **The 3.14 patches add a digit of pi** rather than incrementing:
  3.14.15, 3.14.159, 3.14.1592, 3.14.15926, and finally 3.14.1592653,
  which the wiki's patch list doesn't have.
- **3.6 and 4.3 went public before their wiki dates:** 3.6 on Nov 23,
  2022 (wiki: Nov 29), and 4.3 on Mar 12, 2026 (wiki: Mar 17).
- **4.3.6 was replaced the same day** by an emergency hotfix, 4.3.7.
- **4.4.0 was skipped.** 4.4.1 was the first 4.4 build.
- **No `launcher-settings.json` before 2.4.1** (Oct 2019, the
  Paradox Launcher v2 rollout), so older builds can't be version-detected.

## Hearts of Iron IV

- **1.19.0.0 shipped for ~2 days** before the 1.19.0.1 hotfix replaced
  it. It can't be restored through Steam's beta branches, but its
  depot manifests can still be downloaded directly.
- **1.13.7 was released without announcement.** Its changelog is only
  an ASCII-art image, and its public build is dated Feb 2024, two months
  after the wiki's date.
- **1.13 and 1.14 have no release dates** on the wiki ("unreleased");
  the first public builds were 1.13.1 and 1.14.2.
- **No `launcher-settings.json` before 1.8.2** (Feb 2020), so older
  builds can't be version-detected.

## Victoria 3

- **1.13.2 and 1.13.3 shipped on the same day** (Apr 30, 2026), a few
  hours apart.
- **1.13.10 went public on Aug 12, 2026**, a day after its wiki date.
- **Steam has rollback branches named after old versions** (`1.7.7`,
  `1.8.7`). They're not betas, but they're also not public, so the
  corpus takes those builds from the public history instead.

## Crusader Kings III

- **Two final patches are missing from the wiki's patch list:** 1.11.5
  (the wiki's last 1.11 is 1.11.4) and 1.16.2.3 (its last 1.16 is
  1.16.2.1).
- **1.1.3.1 has no public build.** The wiki dates it Oct 22, 2020, but
  no depot changed between 1.1.3 (Oct 15) and 1.2, and that build
  reports itself as 1.1.3.
- **1.19.0.6's public build is dated June 4, 2026**, ten days after
  the wiki's date.
