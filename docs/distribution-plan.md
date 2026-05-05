# jwm distribution plan

Implementation roadmap for shipping jwm as a paid macOS app with a free tier. Phases are intended to be completed slowly over time. Tick the checkboxes as work lands.

## Locked-in decisions

| Area | Choice |
|---|---|
| Code signing | None (for now) — ad-hoc `codesign -s -` only. No Apple Developer Program. |
| Payments | Lemon Squeezy (abstracted behind a `LicenseProvider` so it can be swapped) |
| License | Offline Ed25519-signed tokens; manual signing via local CLI for v1 |
| Free tier | 100 events/day forever (all 4 `EventKind`s pooled) |
| Capped UX | All hotkeys disabled until local midnight + menubar state + Buy button |
| Anti-cheat | Latest-seen-date watermark in `UsageStats` storage |
| Updates | Sparkle 2 with EdDSA-signed appcast |
| Hosting | GitHub Releases (DMG + appcast) + GitHub Pages (landing page) |
| Price | $7 lifetime |

## Global constraints from "no Apple Developer account"

- DMG triggers Gatekeeper "unidentified developer" warning. Users must right-click → Open, or strip quarantine: `xattr -dr com.apple.quarantine /Applications/jwm.app`.
- Ad-hoc signing (`codesign --sign -`) is **mandatory on Apple Silicon** — entirely unsigned binaries won't launch at all.
- If/when audience grows, getting the $99/yr Apple Dev account is a drop-in upgrade: sign + notarize the same DMG, no other code changes.

---

## Phase 0 — One-time setup (off-repo)

- [ ] Generate Ed25519 **license signing keypair** (`openssl genpkey -algorithm ED25519`). Private key → 1Password; public key → committed to repo.
- [ ] Generate Sparkle **EdDSA keypair** via Sparkle's `generate_keys`. Private key → 1Password; public key → embedded in `Info.plist` as `SUPublicEDKey`.
- [ ] Create Lemon Squeezy account + product. $7 one-time. Enable license keys (their per-purchase opaque key is the buyer-facing identifier we'll map to a signed token).
- [ ] Reserve GitHub repo / Pages site for the landing page + appcast.

**Risks / unknowns**
- Lemon Squeezy account approval can take a few days — start this early.
- Confirm Lemon Squeezy supports adding a custom per-purchase string (signed token) to the buyer's thank-you email. If not, fall back to manual email per sale (fine at low volume).

---

## Phase 1 — License system in-app

- [ ] New `Licensing/LicenseToken.swift` — Codable struct: `{ buyerEmail, issuedAt, schemaVersion, signature }`. Signature is Ed25519 over canonical JSON of unsigned fields.
- [ ] New `Licensing/LicenseVerifier.swift` — verifies signature against embedded public key. Pure function, no I/O. Unit-testable.
- [ ] New `Licensing/LicenseStore.swift` — persists active license to **Keychain** (survives reinstalls; harder to copy between machines casually than UserDefaults).
- [ ] New `Licensing/LicenseStatus.swift` — `enum { .free, .licensed(LicenseToken) }`. Single source of truth, observable so UI reacts.
- [ ] New CLI tool `tools/sign-license/` (Swift package, **not shipped with the app**). Reads `JWM_LICENSE_PRIVATE_KEY` from env. `sign-license --email foo@bar.com` prints a base64 token.
- [ ] Settings UI: new "License" section.
  - Free state: shows `N/100 events used today` + "Buy License" button (opens Lemon Squeezy URL) + "Already bought? Paste license" textarea.
  - Licensed state: shows buyer email + "Remove license" button.
- [ ] Unit tests: valid token verifies; tampered token rejected; expired schema version rejected; wrong key rejected.

**Risks / unknowns**
- Keychain access for non-sandboxed apps requires no entitlements but the API is fiddly; needs a small wrapper. Verify it survives app deletion (default behavior is yes — Keychain items aren't tied to the app bundle).
- "schemaVersion" is forward-compat insurance; pick v1 now and document the upgrade path before issuing the first real license.

---

## Phase 2 — Daily cap enforcement

- [ ] Extend `jwm/UsageStats.swift`: add `static func eventsToday() -> Int` summing all 4 kinds across the 24 local-day hour buckets.
- [ ] Add `static var isCapReached: Bool { LicenseStatus.current.isFree && eventsToday() >= 100 }`.
- [ ] Publish a state-change notification (NotificationCenter or `@Published`) so menubar updates in real time when the cap flips.
- [ ] Wire enforcement at action boundaries: early-return guard in `HotkeyManager.onBeforeAction` (per CLAUDE.md, this is the single chokepoint for chord actions).
- [ ] Confirm mouse-snap actions also flow through (or independently call) the same guard.
- [ ] Menubar UI: capped state shows distinct icon/glyph; clicking opens popover with "Daily limit reached. Resets at midnight." + Buy button.
- [ ] Midnight rollover: `Timer` scheduled to next local midnight to refresh menubar (the underlying counter rolls over naturally because it's computed from hourly buckets).
- [ ] Match the existing release-only guard (`UsageStats.swift:31` skips recording in non-release builds). Cap enforcement must follow the same guard or debug builds trip the cap during dev.

**Risks / unknowns**
- "Disable everything (including focus)" is aggressive — a user hitting 100 mid-afternoon loses their entire workflow. Worth user-testing before announce; the alternative is "disable tile actions, keep focus".
- Verify mouse-snap really does go through `onBeforeAction`. If it has its own path, the guard must be added there too — easy to miss.
- Counting needs to happen **before** the action runs (otherwise the 101st event runs and is then blocked on the 102nd). Order matters.

---

## Phase 3 — Anti-clock-rollback watermark

- [ ] Extend `UsageStats.Store`: add `latestSeenDay: String` field (`yyyy-MM-dd`).
- [ ] On every `record()`: compute `today`. If `today < latestSeenDay`, attribute the event to the watermark day's bucket instead of "today". Otherwise advance the watermark.
- [ ] `eventsToday()` reads from `max(today, latestSeenDay)` so the cap stays effective when the clock is wound back.
- [ ] Document the behavior with a `Why:` comment.
- [ ] Test: simulate clock rollback, verify counter does not reset.

**Risks / unknowns**
- A determined cheater can edit the JSON file directly. Acceptable for v1 — the goal is to block trivial bypasses, not nation-state attackers.
- Remote time check (skipped for v1) would harden this further. Note for v2 if abuse is observed.

---

## Phase 4 — DMG + ad-hoc signing build script

- [ ] New `scripts/build-release.sh`:
  1. `xcodebuild -scheme jwm -configuration Release -derivedDataPath build/`
  2. `codesign --force --deep --sign - --options runtime` the `.app`
  3. Use `create-dmg` (Homebrew) to wrap into a DMG with Applications-folder symlink and a background image
  4. Compute SHA256 of the DMG
  5. Generate Sparkle EdDSA signature with `sign_update`
  6. Output: `jwm-<version>.dmg` + signature line for the appcast
- [ ] Makefile target `release VERSION=...` matching existing `make` style (`.PHONY` per target, no help/comments).
- [ ] Smoke-test the resulting DMG on a clean macOS user account.

**Risks / unknowns**
- `create-dmg` works but the result can look amateurish without a background image — design pass needed before announce.
- Ad-hoc signing is a moving target on macOS. Re-verify on the latest macOS at release time; future macOS versions could tighten the rules.
- Hardened runtime (`--options runtime`) without notarization can occasionally cause runtime issues — test all functionality from the DMG'd binary, not just launch.

---

## Phase 5 — Sparkle integration

- [ ] Add Sparkle 2 via Swift Package Manager.
- [ ] `Info.plist`: `SUFeedURL` → Pages-hosted `appcast.xml`; `SUPublicEDKey` → embedded; `SUEnableAutomaticChecks=YES`; `SUScheduledCheckInterval=86400`.
- [ ] Wire `SPUStandardUpdaterController` into the app delegate; add "Check for Updates…" menu item.
- [ ] Confirm updates work regardless of license state (license lives in Keychain, untouched by app updates).
- [ ] End-to-end test: ship v1.0.0, then v1.0.1 noop, watch v1.0.0 update itself on a fresh user account.

**Risks / unknowns**
- **Biggest unknown of the whole plan.** Sparkle on unsigned apps: docs say it works but there are edge cases around quarantine attributes and app translocation. Needs end-to-end testing on a fresh user account before announcing v1.
- After update, the new bundle may inherit quarantine and re-trigger Gatekeeper. Sparkle's installer typically clears `com.apple.quarantine`; verify by inspection.

---

## Phase 6 — Landing page (GitHub Pages)

- [ ] Static site, single `index.html` + minimal assets.
- [ ] Sections: hero (what is jwm, GIF demo), Download → latest Release DMG, prominent first-time install instructions (right-click → Open), pricing pitch ("Free 100 events/day, $7 lifetime to remove the limit"), Buy button → Lemon Squeezy hosted checkout.
- [ ] Host `appcast.xml` at the same Pages site.
- [ ] Privacy / terms blurbs (lightweight — what data is collected, namely none beyond local usage stats).

**Risks / unknowns**
- Quality of the landing page directly affects conversion. Worth more time than the bare minimum, but resist gold-plating.
- Lemon Squeezy checkout URL format/stability — confirm the link can be hardcoded long-term.

---

## Phase 7 — Release v1.0.0

- [ ] Bump version in Xcode project.
- [ ] `make release VERSION=1.0.0`.
- [ ] Create GitHub Release; attach DMG.
- [ ] Update `appcast.xml` with new entry (release notes, version, EdDSA signature, DMG URL, content length). Commit + push to Pages repo.
- [ ] **Full loop test on a clean macOS user account**: download → install → use → hit cap → buy (use a Lemon Squeezy test transaction) → paste license → confirm unlimited.
- [ ] Verify Sparkle path: publish a v1.0.1 noop and watch v1.0.0 update itself.
- [ ] Announce.

**Risks / unknowns**
- First-purchase manual signing dance: walk through it end-to-end before announce so you know the buyer experience isn't broken.
- "Test transaction" semantics in Lemon Squeezy — confirm there's a sandbox / test-mode that doesn't actually charge.

---

## Future / v2 ideas (not in scope for v1)

- Cloudflare Workers automation: receive Lemon Squeezy webhook, sign license, email buyer. Removes manual signing.
- Remote time check to harden anti-cheat.
- Reconsider "disable everything" cap UX in favor of "disable tile actions, keep focus" if users complain.
- Apple Developer account → notarization → no Gatekeeper warning.
- Online activation API (Lemon Squeezy native) for license revocation if abuse appears.
