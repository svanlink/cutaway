# Cutaway Loop Journal

Autoresearch-style state: what was tried, what happened, kept or reverted.
Newest entries at the top. Readiness score updates with each [ship] entry.

Readiness: 4/6 proven (R-INSTALL, R-BACKUP, R-DEGRADE, R-LOCALE, R-DOCS, R-RELEASE)

---

## 2026-07-19 ~03:40 — [ship] R-LOCALE — KEPT
All formatters pinned to en_US_POSIX: currency (was separator-pinned only,
now digit/sign-proof too) and CSV date/weekday/time (was OS-calendar
dependent — a Thai-locale Mac would have exported Buddhist-era years).
3 exact-output tests across all 4 currencies. One test expectation was
wrong, not the app: formatWhole truncates (12'345.67 -> 12'345), kept as
correct under-billing behavior and documented. Gate 86/86 + smoke ALL PASS.

## 2026-07-19 ~03:30 — [ship] R-DEGRADE — KEPT
fuscript now found via LaunchServices (wherever Resolve is installed) with
stock-path fallbacks; injectable candidates make it testable. 2 tests:
missing fuscript -> nil (no crash), nonstandard path found. Smoke doubles
as the no-Resolve proof (whole app runs without Resolve present).
Gate 83/83 + smoke ALL PASS.

## 2026-07-19 ~03:20 — [ship] R-BACKUP — KEPT
StoreBackup: launch-time trio copy (store/-wal/-shm) before the container
opens, byte-compare skip, keep-7 rotation. 4 new tests (copy/skip/rotate/
no-op). Real double-launch proof: Backups/billing-20260719-025041 holds the
trio. One iteration hiccup: forgot xcodegen after adding the file — compile
fail, fixed by regenerate. Gate 81/81 + smoke ALL PASS.

## 2026-07-19 ~03:05 — [ship] R-INSTALL — KEPT
Ad-hoc codesign step added to release.sh (sign → verify → zip). Proof:
Release build signed (flags=0x2 adhoc), codesign --verify strict OK,
quarantined copy launches after documented xattr -cr. Caveat: this Mac has
Gatekeeper disabled (spctl override), so the warning dialog itself is
untestable here — stock-Mac path documented in cask caveats (right-click
Open / --no-quarantine). Tap updated + brew audit clean. Gate 77/77 + smoke.

## 2026-07-19 ~02:50 — loop upgraded to autoresearch mechanics
Researched karpathy/autoresearch + bilevel loop engineering. Adopted:
per-iteration budget, failure journaling (this file), bilevel re-plan rule
after 2 consecutive reverts, single readiness metric for the 06:00
production push. Backlog rewritten around the readiness checklist.

## 2026-07-19 ~02:30 — [design] Settings grouped sections — KEPT (96571c6)
Blind panel 3/3 for grouped design (8 vs 4-5). Judges found real defects:
subtitle truncation + low contrast → new goal in Later. Gate green.

## 2026-07-19 ~02:15 — [stability] Editable app lists — KEPT (d01dcc4)
Settings editor popovers, live engine pickup, sanitizer. 77/77 + smoke.

## 2026-07-19 ~01:50 — [stability] Rename/delete projects — KEPT (210003c)
One compile failure mid-iteration (missing SwiftData import) — fixed,
gate then green on first re-run. 75/75 + smoke.
