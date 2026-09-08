# Cutaway → premium: the audit and the plan
*Generated 2026-09-05 | Inputs: 5 cited research reports (≈170 sources) + an internal code audit | Confidence: High on distribution/design/detection, Medium on billing scope*

Companion reports (all in this folder, all cited):
- `2026-09-05-competitors-premium-ux.md` — what Timing, Timemator, Tyme, Klokki, Toggl, Harvest, Rize, Hours, Timely do; feature matrix; pricing; onboarding
- `2026-09-05-design-language-macos.md` — Liquid Glass, premium Mac visual patterns, menu-bar specifics, appearance, accessibility
- `2026-09-05-engineering-distribution.md` — Developer ID/notarization, Sparkle, App Store question, diagnostics, energy, code structure, 7 exemplar repos
- `2026-09-05-billing-invoicing.md` — what editors bill, invoice PDF, Swiss QR-bill, VAT/reverse-charge, rounding, complaints
- `2026-09-05-detection-intelligence.md` — how the best trackers detect work and documents, Adobe/Resolve specifics, idle logic, energy and privacy

## The verdict in one paragraph

Cutaway's engine is already at the premium bar — the under-billing rules, rate history and the adjusted-hours trace are things reviewers *wish* the paid apps had. What is not at the bar is everything around the engine: the app cannot be launched by a normal buyer on macOS 15/26 (ad-hoc signature), it cannot update itself, it says nothing when a save fails, it speaks one language, it has no timeline to fix a wrong day, no PDF a client can receive, no client or invoice concept, and it reads only Resolve's project name. None of that requires touching the billing engine. The plan below keeps the engine sacred and rebuilds the shell around it.

## Part A — What the code says about itself (internal audit)

Measured on `main` @ aaeb538 (v1.2.0).

| Signal | Value | Premium bar | Verdict |
|---|---|---|---|
| Size | 5,566 lines, 8 feature folders, 0 dependencies | — | Small and honest. Good. |
| Tests | 325 unit + 7 UI, smoke harness ×8 scenarios | Billing invariants proven | Strong. This is the moat. |
| Swallowed errors | 37 × `try?` in Sources | A save never fails silently | Weak: every store write must surface failure (banner + log). |
| Force unwraps | 1 × `try!`, 4 × `!` | 0 in shipping paths | Acceptable (the `try!` is the guarded in-memory fallback). |
| Localization | 0 localized strings, 66 hard-coded UI strings, no `.lproj` | String Catalog; en + de at least | Missing. |
| Appearance | `preferredColorScheme(.dark)` in 7 views | One app-level decision | Fragile; per-view forcing is what App Review rejects (design report §4). |
| Signing | ad-hoc, hardened runtime off, no entitlements | Developer ID + notarization + hardened runtime | The biggest "not professional" tell. On macOS 26 the app is sent to the Trash on first launch (engineering report §1). |
| Bundle metadata | no app category, empty copyright, legacy `.icns` icon | Category, copyright, Icon Composer icon | Missing; cheap. "Icon jail" on macOS 26 (design report §1). |
| Updates | none (brew only) | Sparkle 2 | Missing. |
| Diagnostics | none | MetricKit + opt-in local export, no telemetry | Missing. |
| Engine | 1 × Timer @1 Hz, tolerance 0.5 s, polls frontmost + idle | Event-driven where possible | Adequate; two cheap upgrades (detection report §1). |
| Largest files | 469 / 429 / 426 / 408 lines | < 400 | Borderline; no action. |

## Part B — The plan, ranked

Effort: S = a day or less, M = 2–5 days, L = more. Every item cites the report that justifies it.

### Ship next: v1.3 "Trust" — the release that makes it a real product

| # | What | Why | Effort / cost |
|---|---|---|---|
| 1 | **Developer ID + notarization + hardened runtime**, DMG + zip, stapled | macOS 15 removed the right-click bypass; macOS 26 trashes ad-hoc-signed downloads. Every ≥10k-star menu-bar app does this. TCC grants stop resetting on rebuild. — engineering §1, competitors #6 | S · $99/yr |
| 2 | **Tag-driven GitHub Actions release** (archive → notarize → DMG → release notes), replacing `release.sh` | Reproducible, no laptop in the loop; pattern copied from a surveyed repo — engineering #2 | M · free |
| 3 | **Sparkle 2 updates** with signed appcast on gh-pages; cask `auto_updates true`; disclosed in Settings as *the one* network call, user-toggleable | The only network call, and the one users expect; brew and in-app must not fight — engineering #3 | M · free |
| 4 | **Surface save failures** (replace 37 `try?` on store writes with a visible banner + local log) | A billing app that loses a save silently is not premium; this is the cheapest credibility fix — internal audit | S |
| 5 | **App-level appearance decision** (`NSApp.appearance = .darkAqua` once, documented as a media-instrument exception; remove the 7 per-view forces) + verify Increase Contrast × Reduce Transparency | Apple calls forced dark "rare cases"; half-done light modes get rejected — design #3 | S |
| 6 | **Icon Composer app icon**, app category, copyright, version stamping already done | Legacy `.icns` = "icon jail" on macOS 26; missing metadata reads amateur — design #2, audit | M |
| 7 | **Permissions primer on first run**: one row per permission with the concrete reason and live status; explicit "never Screen Recording, never keystrokes, nothing leaves your Mac" | What Timing/Rize do in the first 2 minutes; the honesty stance becomes visible — competitors #7, detection #8 | S |
| 8 | **Global shortcuts + Shortcuts.app actions** (Pause/Resume, Today, Project total, Switch project) | Keyboard-first is the most-praised Mac-native trait — competitors #5 | S |
| 9 | **Event-driven detection**: `didActivateApplicationNotification` for app switches, `AXObserver` for Resolve's title, keep the 1 Hz idle read; stop the timer when nothing can record | Apple's polling guidance; measurable energy win — detection #1, engineering #4 | M |
| 10 | **Local-only diagnostics**: MetricKit crash/hang capture to disk + "Copy report" in Settings | Reliability without telemetry; the exemplars do the same — engineering #5 | M |

### Next quarter: v1.4 "Invoice" and v1.5 "Timeline"

| # | What | Why | Effort |
|---|---|---|---|
| 11 | **Day timeline in Stats**: sessions on a strip; trim / split / reassign | 9 of 10 competitors; the fix for "left the timer on during lunch" — competitors #1 | M |
| 12 | **Invoice PDF from a period** (`INV-YYYY-NNNN`, supplier/client blocks, per-day rows, adjusted-hours shown, total) via ImageRenderer | CSV-only reads unfinished; 8/10 export PDF — billing #1, competitors #3 | M |
| 13 | **Client entity + tax mode** (CH 8.1 % + UID / below threshold / EU reverse charge / other), CHF rounding to 0.05 | Legal correctness for a Swiss freelancer with EU/US/CO clients — billing #4 | M |
| 14 | **Swiss QR-bill on CHF/EUR invoices** | "This is the premium signal" for the owner's market — billing #5 | M |
| 15 | **Unbilled / invoiced / paid status + lock on invoice**; unbilled total in the panel | Kills the top two invoicing complaints — billing #2 | S |
| 16 | **Rounding per project, always down or nearest, raw seconds kept beside it** | Honesty-compatible; Hours/Toggl/Timemator/Tyme all offer it — billing #3, competitors #10 | S |
| 17 | **Day rate + minimum units as "booked, not worked" lines**; manual lines (deposit, revision round, kill fee) | What editors actually bill — billing #6–7 | M |
| 18 | **Adobe project names via Automation** (After Effects, Photoshop, Illustrator, InDesign on app-activation only). Premiere explicitly excluded (no dictionary, title hidden) | Attribution for the Adobe half of the owner's day; one Automation prompt per app — detection #2–3 | M |
| 19 | **Display-sleep-assertion presence rule** (frontmost anchor holds `PreventUserIdleDisplaySleep` → present), cap kept; replaces the CPU heuristic | Timing's rule; covers playback/review, cheaper — detection #4 | S |
| 20 | ~~String Catalog + German~~ — **moved into v1.3** by decision 6 | Owner's market; premium apps ship ≥2 languages — audit | M |
| 21 | **`CutawayCore` package** (no AppKit) with its own tests; `VersionedSchema` + no-op migration plan for SwiftData | The one structural win at this size; migration safety — engineering #6–7 | M |
| 22 | **Desktop widget** (today + money + pause) | Tyme, Timery, Hours, Rize ship one — competitors #9 | M |

### Not doing, and why

- **Mac App Store** — sandbox breaks `fuscript`; helper-process rules invite rejection (engineering #8).
- **iCloud / CloudKit sync** — contradicts local-only; Timemator's top crash complaint; paid capability (engineering #8, competitors).
- **Subscription pricing** — hostile reviews in this category; one-time $39–49 with 12 months of updates and a perpetual fallback is the accepted norm; Setapp as a second channel later (competitors §3).
- **Screen Recording permission / Premiere title scraping** — monthly Sequoia nag, privacy cost; Premiere stays an anchor without a project name (detection #3).
- **Stripe links, reminders, client portal, retainer ledgers** — need a server or account (billing #8).
- **Pomodoro, coaching, Liquid Glass inside content** — off-brand; Apple says glass only on the navigation layer (design §1).

## Part C — Where the research contradicts decisions already taken

Named here so nothing is changed by stealth.

1. **Reclaim offer (removed 2026-09-05, spec Part 4, decision Q12-B).** Competitors report the "Away 47 min — keep, drop, or assign?" prompt is *the* feature that sold reviewers on Timemator and Klokki (competitors #2). Recommendation: do not resurrect the card; ship the **timeline** (#11), which covers the case with a trace and without a prompt. If you want the prompt back, it must default to *drop* and honour the 5-min floor / 10-h ceiling from the detection report (#5).
2. **Notification vs card (spec Part 1 vs Part 4).** Stays a card. The detection report adds a floor and ceiling and "return focus to the previous app after dismiss" — apply to both cards (#5 there).
3. **Forced dark (spec Part 4 "Look").** Kept, but the design report says it must be a single app-level decision, not seven `preferredColorScheme` calls, and it must survive Increase Contrast × Reduce Transparency and macOS 26.1's Clear/Tinted variants (plan #5).
4. **Render exemption (CPU heuristic).** The detection report prefers the display-sleep assertion (plan #19). Keep the opt-in, swap the evidence.
5. **"Launch at login" kept against the spec list** — confirmed right; no report suggests removing it.

## Part D — Decisions only you can make

1. **Buy the Apple Developer Program now ($99/yr)?** Everything in "Trust" hangs on it. Without it, the next release still trashes on macOS 26 for new users.
2. **Price and model for the next public release:** one-time CHF 39–49 with 12 months of updates (recommended), or free/open-source stays?
3. **Dark-only, documented as an instrument exception — or a light theme too?** Dark-only is one afternoon; a light token set is a week and a second contrast suite.
4. **Adobe project names via Automation permission** — one prompt per Adobe app, on first activation. Yes/no.
5. **Order of the quarter:** Invoice (PDF + client + QR-bill) before Timeline, or Timeline first?
6. **German localization** in v1.3 or later?

## Decisions taken (2026-09-05, owner)

| # | Decision | Consequence for the plan |
|---|---|---|
| 1 | Apple Developer Program: **not yet** | Plan #1 (notarization) and #3 (Sparkle) are parked. v1.3 ships #2, #4–#10. New users on macOS 15/26 keep the Gatekeeper wall; the README's right-click/`--no-quarantine` guidance stays. Revisit before any paid or public push. |
| 2 | Pricing: **free / open source** | No licensing, no trial, no Setapp. "Trust" is polish for reputation, not conversion. |
| 3 | Appearance: **dark-only, done properly** | Plan #5 as written: one app-level decision, documented exception, verified under Increase Contrast × Reduce Transparency and macOS 26.1 variants. No light token set. |
| 4 | Quarter order: **Invoice first** | v1.4 = #12–#17 (PDF, client + tax mode, QR-bill, billing status, rounding, day rates). v1.5 = #11 timeline. |
| 5 | Adobe project names via Automation: **yes, in the Invoice quarter** | Plan #18 confirmed for v1.4: After Effects, Photoshop, Illustrator, InDesign read on app-activation only, one Automation prompt per app, explained in the primer. Premiere Pro stays excluded (needs Screen Recording — refused). |
| 6 | German localization: **v1.3, with the String Catalog** | Plan #20 moves from "next quarter" into v1.3. Every string born localizable from now on; the 66 hard-coded literals migrate in that pass. |

## Part E — Your prompt, optimized

Diagnosis of the original ("do the thoroughest research ever … make it premium … unrecognizable"):

Strengths: names the outcome (premium, professional, fast), authorizes subagents and graphify, asks for plain language, and asks me to fill in what you did not think of.

| Issue | Impact | Fix |
|---|---|---|
| No definition of "premium" | Every researcher answers a different question | Name the reference apps and the yardstick |
| "Unrecognizable" conflicts with "grab this beautiful program we built" | Risks discarding the honesty engine that is the product | State what is sacred |
| No decision owner / budget / order | Research without a cut-off never ends | Cap sources; ask for a ranked list with effort; decide in one sitting |
| No acceptance test for the research itself | Cannot tell done from not done | "Done when: 5 cited reports, one synthesis with a ranked plan, graph updated" |
| Token-saving asks are vague | I cannot act on "use caveman" alone | Say which outputs may be terse and which must be full |

Paste-ready version:

```
Research and plan the next version of Cutaway so it feels as premium and professional as the best paid Mac apps, without losing what makes it honest.

Sacred (do not propose removing): the under-billing engine (anchors, satellites, bridge, sacred pause, rate history, adjusted-hours trace), local-only data (no account, no network), the menu-bar-first shape decided on 2026-09-04.

Yardstick: Timing, Timemator, Tyme, Raycast, Things 3, CleanShot X. "Premium" means: native macOS 26 feel that still runs on 14, one-time purchase, notarized, auto-updating, keyboard-first, accessible, and a Stats/report surface a client could receive.

Do:
1. Run 5 research agents in parallel (competitors & UX, macOS 26 design language, distribution & engineering, freelancer billing/invoicing, activity & project detection). Each writes a cited report (≤1800 words, ≤18-month-old sources, "insufficient data" where true) to docs/research/2026-09-05-<topic>.md.
2. Audit the code yourself for: swallowed errors, localization, appearance handling, signing/entitlements, update/crash tooling, energy of the 1 Hz engine.
3. Synthesize into docs/research/2026-09-05-premium-audit.md: one ranked plan (what / why with citation / effort S-M-L / cost), grouped into "ship next release", "next quarter", "not doing and why". Flag any recommendation that contradicts a decision in docs/superpowers/specs/2026-09-04-final-form-design.md.
4. Ingest the reports into graphify (docs/research as a corpus) and confirm `graphify query` answers "what makes a Mac time tracker premium" from them.
5. Reply in plain language: the top 10 changes in one screen, then the decisions only I can make as multiple-choice questions.

Do not: write feature code in this pass; propose removing local-only or under-billing; recommend subscriptions without a comparison to one-time pricing; exceed 3 clarification questions.

Token rules: research reports and the synthesis in full; chat replies terse (caveman) except the top-10 list and the decisions.

Done when: five reports + synthesis exist and are committed, graph updated, and I have answered the decisions.
```

Quick version: `Use deep-research (5 parallel agents) on: competitors UX, macOS 26 design, distribution/engineering, billing, detection. Audit code. Synthesize ranked plan in docs/research. /graphify docs/research. Reply top-10 + decisions.`

## Open item carried from earlier today

"The app picker shows Resolve as not installed" (reported after the 1.2.0 upgrade). Verified: the installed binary is the fixed build, the scan finds `/Applications/DaVinci Resolve/DaVinci Resolve.app` when run standalone, no sandbox, no access-denial logs. Not verified: what the sheet actually shows on the owner's screen — my clicks were blocked by a window-manager overlay and the UI-test runner then failed to enable automation mode. Needs one screenshot from the owner, or a retry once the automation daemon recovers.

---

# Re-score, 2026-09-08

Part A measured again against the branch at `be229ef`, three days and two
releases later. Same signals, same yardstick. Measured, not remembered.

| Signal | 2026-09-05 (v1.2.0) | 2026-09-08 | Verdict |
|---|---|---|---|
| Size | 5,566 lines, 8 folders, 0 deps | 8,258 lines, 62 files, 8 folders, **0 deps** | Grew 48 % — invoice, recovery, undo. Still no dependency. |
| Tests | 325 unit + 7 UI, 8 scenarios | **418 unit + 10 UI**, 8 scenarios | Stronger. The moat held while the app grew. |
| Swallowed errors | 37 × `try?`, store writes among them | **0 swallowed saves** (48 `try?`, none on a save; 12 are cleanup `removeItem`) | **FIXED** |
| Force unwraps | 1 × `try!`, 4 × `!` | 1 × `try!` (the guarded in-memory fallback) | Unchanged, still acceptable |
| Localization | 0 localized, 66 hard-coded strings | **String Catalog, 233 keys, 233 German** | **FIXED** |
| Appearance | `preferredColorScheme` in 7 views | **0** — one app-level decision | **FIXED** |
| Signing | ad-hoc, no hardened runtime | ad-hoc, no hardened runtime | **Settled 2026-09-08: staying that way.** Free, Homebrew-published; the cask strips quarantine. Not a gap — a chosen trade-off with two accepted costs (a hand-downloaded zip needs `xattr -d`; a rebuild drops the Accessibility grant). |
| Bundle metadata | no category, empty copyright, legacy `.icns` | category ✓, copyright ✓, **still `.icns`** | Mostly fixed; Icon Composer icon still owed |
| Updates | none | none (parked by decision 1) | Unchanged by choice |
| Diagnostics | none | MetricKit capture + reveal | **FIXED** |
| Engine | 1 × Timer @1 Hz | **1 repeating timer** — backup folded onto it | Improved |
| Largest files | 469 / 429 / 426 / 408 | 455 / 453 / 440 / 417 | **FIXED 2026-09-08** (31e5283). `AppModel` 639 → 455; the launch path, the detection schedule and crash recovery moved to files that own them, and gained twelve tests that could not exist before. |

## Signals the original audit had no row for

These are where the last three days actually went.

| Signal | Was | Now |
|---|---|---|
| Money exactness | `Double` everywhere; CSV and Stats disagreed on ~3 months in 4 | One rounding rule, ties to the client; `Decimal` for everything frozen or printed |
| Recovery | A lock or a full disk could trigger a restore over good data; a zero-byte store passed as healthy | Four-way verdict; **the store is never replaced without a yes** |
| Backups openable | **2 of 12** — filename matching locked out every backup that ever saved this Mac | **12 of 12**, matched by content across two renames |
| Client-facing artefact | CSV only | Invoice PDF, vector text, with the typed-time trace printed on the page |
| Reversibility | A day edit destroyed sessions permanently | ⌘Z restores spans and adjusted flags exactly |
| Accessibility | UI audit red; 5 controls with no label | Audit green; every control speaks |
| Attribution completeness | InDesign hours tracked as nothing | Anchored by default, pinned by test |
| Swiss payment | none | QR-bill payload exact and tested; layout needs one validation run |

## The scores that are actually claims

**Readiness: 6/6 → 5/6.** `R-INSTALL` was marked PROVEN on 2026-08-20 and is
no longer true as written: macOS 15 removed the right-click bypass and macOS 26
reports an ad-hoc-signed download as damaged. Homebrew still works because the
cask strips quarantine. Corrected in `GOALS.md` rather than left standing.

**Premium bar: the engine was already there; the shell was not.** Of the ten
"ship next" items, seven are done, two are parked by decision (notarization,
Sparkle), and one — the Icon Composer icon — is simply owed. Of the next
quarter's eight, five are done in the last two days.

## What the numbers say to do next

1. ~~**`AppModel` at 639 lines**~~ — done, 31e5283. No file is over 455.
2. ~~**The $99 signing decision**~~ — decided on 2026-09-08: no notarization,
   Homebrew stays the channel. Every other "not professional" tell from
   2026-09-05 is closed, and this one is now a documented choice rather than
   an open item.
3. **A slow test remains unexplained**: the suite takes 9 s or 250 s, always
   attributed to `AppearanceGuardTests`, which runs in 0.017 s alone. Two
   theories tested and disproved. It costs minutes per gate, not correctness.
