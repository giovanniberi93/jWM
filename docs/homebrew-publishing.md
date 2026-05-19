# Publishing jwm to Homebrew (free path)

This is the checklist for shipping the **first** version of jwm via Homebrew Cask without paying for the Apple Developer Program. It is written for Claude Code to execute: tick boxes as steps complete, and read the **Context** section before starting each phase.

## Context — choices already made

- **Distribution channel**: personal Homebrew tap at `giovanniberi93/homebrew-jwm`. NOT the official `Homebrew/homebrew-cask` repo (that requires Developer ID signing + notarization, both gated by the $99/yr Apple Developer Program).
- **Signing**: ad-hoc only (`codesign --sign -`). No Developer ID. No notarization.
- **User-side consequence**: first launch will hit Gatekeeper. Users must right-click → Open → Open, OR run `xattr -dr com.apple.quarantine /Applications/jWM.app`. Document this prominently in the tap README and main README.
- **Accessibility permission caveat**: ad-hoc signatures change cdhash on each build, so TCC may force users to re-grant Accessibility after every upgrade. Acceptable tradeoff for v1; revisit if it becomes a frequent complaint.
- **Source repo**: `git@github.com:giovanniberi93/jWM.git` (origin).
- **App identity**: bundle id `com.giovanniberi93.jwm`, product/display name `jWM`, app bundle path after install: `/Applications/jWM.app`.
- **Versioning**: `scripts/generate_version.sh` derives version from `git describe --tags --match 'v*'`. Release tags must follow `vX.Y` (e.g. `v0.1`). Avoid `vX.Y.Z` unless the version script is updated first — it currently treats the third component as commit count.
- **Build config**: Makefile only has Debug targets today. A `release` target needs to be added (see Phase 1).

If any of these choices look stale when you re-read this doc, STOP and re-confirm with the user before proceeding.

## Phase 1 — Repo prep (one-time)

- [ ] Add a `release` target to `Makefile` that runs `xcodebuild -project jwm.xcodeproj -scheme jwm -configuration Release -derivedDataPath build/release build`, producing `build/release/Build/Products/Release/jwm.app`.
- [ ] In the Xcode project's Release config, confirm `CODE_SIGN_IDENTITY = "-"` (ad-hoc) and `CODE_SIGN_STYLE = Manual` so the build doesn't require a team. Hardened runtime is fine to keep on but not required.
- [ ] Verify `scripts/generate_version.sh` runs in Release builds (it's wired via a Run Script build phase — check the phase is enabled for Release).
- [ ] Confirm the Release build launches cleanly: `make release && open build/release/Build/Products/Release/jwm.app`. The displayed version should NOT contain `(dev)` (that suffix is Debug-only).
- [ ] Add a release packaging script `scripts/package_release.sh` that: (a) calls the release build, (b) re-signs ad-hoc with stable identifier (`codesign --force --deep --sign - --identifier com.giovanniberi93.jwm build/release/Build/Products/Release/jwm.app`), (c) zips it into `build/release/jWM-<version>.zip` using `ditto -c -k --sequesterRsrc --keepParent` (NOT `zip` — that strips macOS metadata and breaks the bundle).
- [ ] Update root `README.md` with an "Install via Homebrew" section. Include the `brew tap` + `brew install --cask` commands, AND the Gatekeeper bypass instructions (right-click → Open, or `xattr -dr com.apple.quarantine`).

## Phase 2 — Create the tap repo (one-time)

- [ ] Create the GitHub repo: `gh repo create giovanniberi93/homebrew-jwm --public --description "Homebrew tap for jwm"`. Name MUST start with `homebrew-` for Homebrew to recognize it as a tap.
- [ ] Clone it to `/Users/giovanni.beri/workspace/homebrew-jwm`.
- [ ] Create directory structure: `Casks/` at the repo root.
- [ ] Write `README.md` in the tap repo with install instructions (`brew install --cask giovanniberi93/jwm/jwm`) and the Gatekeeper bypass note.

## Phase 3 — First release artifact

- [ ] In the main jwm repo on `main`, decide the first version. Default: `v0.1`. Confirm with the user before tagging.
- [ ] Tag and push: `git tag v0.1 && git push origin v0.1`. Tagging BEFORE building is important — the version script reads `git describe`, so the build embeds the right version.
- [ ] Run `make release` then `./scripts/package_release.sh` (built in Phase 1). Output: `build/release/jWM-0.1.zip`.
- [ ] Sanity check the zip: unzip to a temp dir, `open jWM.app`, confirm version string shows `0.1.0+<sha>` (no `-dirty`, no `(dev)`).
- [ ] Compute the SHA256: `shasum -a 256 build/release/jWM-0.1.zip`. Save the hex digest.
- [ ] Create the GitHub release and upload the zip:
  ```
  gh release create v0.1 build/release/jWM-0.1.zip \
    --title "v0.1" \
    --notes "First Homebrew release. See README for install instructions."
  ```
  Keep the release notes terse — the user can edit them after.

## Phase 4 — Write the cask

- [ ] In the tap repo, create `Casks/jwm.rb` with this skeleton (fill `version` and `sha256` from Phase 3):
  ```ruby
  cask "jwm" do
    version "0.1"
    sha256 "<sha256-from-phase-3>"

    url "https://github.com/giovanniberi93/jWM/releases/download/v#{version}/jWM-#{version}.zip"
    name "jWM"
    desc "macOS tiling window manager with chord-based focus and tiling"
    homepage "https://github.com/giovanniberi93/jWM"

    livecheck do
      url :url
      strategy :github_latest
    end

    depends_on macos: ">= :sonoma"

    app "jwm.app", target: "jWM.app"

    zap trash: [
      "~/Library/Preferences/com.giovanniberi93.jwm.plist",
      "~/Library/Application Support/com.giovanniberi93.jwm",
      "~/Library/Caches/com.giovanniberi93.jwm",
      "~/Library/HTTPStorages/com.giovanniberi93.jwm",
    ]

    uninstall quit: "com.giovanniberi93.jwm"

    caveats <<~EOS
      jwm is distributed unsigned. On first launch macOS will block it.
      Either right-click jWM in Applications and choose Open, or run:
        xattr -dr com.apple.quarantine /Applications/jWM.app

      jwm needs Accessibility permission. Grant it in:
        System Settings → Privacy & Security → Accessibility
    EOS
  end
  ```
- [ ] Confirm `MACOSX_DEPLOYMENT_TARGET = 14.0` is still set in `jwm.xcodeproj/project.pbxproj`. If it changes, update `depends_on macos:` to match (`:sonoma` = 14, `:sequoia` = 15, `:tahoe` = 26).
- [ ] Confirm the bundle name on disk is `jwm.app` (lowercase). The Release build emits `build/Build/Products/Release/jwm.app`, and `package_release.sh` zips that path, so the zip contains `jwm.app`. The cask's `app "jwm.app", target: "jWM.app"` line renames it to `jWM.app` at install time.
- [ ] Run `brew install --cask --debug --verbose ./Casks/jwm.rb` locally from the tap repo to test end-to-end. Then `brew uninstall --cask --zap jwm` to verify zap removes preferences cleanly.
- [ ] Run `brew style ./Casks/jwm.rb` and fix anything it flags. Skip `brew audit --new-cask` — it's strict and only matters for `homebrew/cask` submissions.
- [ ] Commit and push the cask to the tap.

## Phase 5 — End-to-end smoke test as a user would do it

- [ ] On a clean shell (`brew untap giovanniberi93/jwm` first if previously tapped):
  ```
  brew tap giovanniberi93/jwm
  brew install --cask jwm
  ```
- [ ] Confirm `/Applications/jWM.app` exists.
- [ ] Confirm the Gatekeeper bypass instructions in the caveats actually work.
- [ ] Launch the app, grant Accessibility, confirm chord-based tiling works.
- [ ] `brew uninstall --cask --zap jwm` and confirm the app and preferences are gone.

## Phase 6 — Announce / document

- [ ] Update the main `README.md` install section if anything in Phases 1–5 changed the exact commands.
- [ ] Optional: add a screenshot/gif of the Gatekeeper bypass to the README so first-time users aren't surprised.

## Reference — for future releases (not part of first publish)

For subsequent versions, the loop is:
1. Tag `vX.Y` on main, push tag.
2. `make release && ./scripts/package_release.sh`.
3. `gh release create vX.Y build/release/jWM-X.Y.zip --notes "…"`.
4. In the tap repo, update `version` and `sha256` in `Casks/jwm.rb`, commit, push.

This whole loop is a candidate for a GitHub Actions workflow once the first release proves the pipeline. Out of scope for this doc.
