# Cutaway — the plan, 2026-09-07

From a six-department review (`docs/research/2026-09-07-*.md`) and three
arbitrations. Every claim below was verified in the code, not taken on trust.

## The doctrine, in one line each

1. The timer is a consequence, not a button.
2. Every ambiguity resolves toward under-billing.
3. Local forever — no account, no network, no telemetry.
4. The menu bar is the app; Stats and Settings are rooms you visit.
5. Resolve-first, not a generic freelancer tracker.
6. Corrections are allowed, but they leave a scar.

**"Exactly how much to charge" is a provenance claim, not a precision claim.**
For any number the app shows, it must name the sessions behind it and mark each
*tracked* or *entered*, in two clicks. That is the shipping test.

## Four tests every feature must pass

| Test | The question |
|---|---|
| Provenance | Can the app name the sessions behind this number, and who decided each? |
| Consequence | Does this happen because they worked, or because they configured something? |
| Default | Ship the value that is right. A setting is only justified by a contract, never a taste. |
| Silence | Does the app get quieter? Two interruptions exist; a third must replace one. |

## Done tonight — 054c150

| Fix | Was costing |
|---|---|
| InDesign added to the default anchors | Every InDesign hour tracked as nothing |
| One rounding rule (`Money.round2`, ties down) | CSV said 45.13 where Stats said 45.12 |
| Edit-day sheet carries its own project | Corrections saved onto the wrong project |
| Day ends at the next midnight | Spring-forward edits landed on the next day |
| Backups follow the store | Test runs wrote into the real backups folder |
| Scratch prefs clean up after themselves | 4'103 files in ~/Library/Preferences |

Gate: 368 unit tests green, smoke ×3 ALL PASS.

## v1.3.2 "Quiet" — COMPLETE 2026-09-08

1. **Store recovery rework** (arbitration): a four-way verdict — absent /
   usable / unreadable / damaged. An unreadable store (permissions, disk full,
   a Time Machine lock) NEVER triggers recovery. A zero-byte or foreign-schema
   store IS damaged. **The app may never replace a live store without a yes** —
   a modal naming the reason, the candidate backup, its age and session count.
2. **Restore matches backups by content, not filename** — all twelve of the
   owner's existing backups open, across the `default.store` → `timex.store` →
   `billing.store` rename history. Today ten of twelve are unopenable.
3. **Retention**: the oldest generation is pinned forever; `.replaced-*` copies
   reaped after 30 days.
4. **One repeating timer** (arbitration): the engine tick — 1 s while recording,
   5 s when hard-paused, invalidated only on sleep. The backup check folds into
   it keyed on wall-clock, never a tick counter. `backupTimer` goes.
5. **Delete the render exemption** — the only rule billing seconds no human
   caused. Not re-evidenced: Resolve holds the display-sleep assertion during
   renders, so that evidence is no better. Long renders are the idle threshold's
   job, and typing the time into the day editor leaves a pencil.
6. **Settings 15 → 7**: idle threshold (kept and promoted), apps that count,
   research & comms, default rate, default currency, launch at login, restore.
   Auto-resume moves into the card; pill modes, both backup buttons and the raw
   bundle-ID editor die. Permissions folds in — it is a fourth window today.
7. **Fix the two accessibility-audit failures** (unlabelled Settings pickers) —
   the UI gate is red until they pass.
8. **Undo** — one `UndoManager`, ⌘Z in Stats and the panel. Precondition for
   everything editable that follows, and the fix for a day edit destroying real
   sessions when it shrinks a day.
9. README: delete the stale "Your data" section, correct the test count, and
   stop selling `brew install` as a working path on macOS 26.

## v1.4 "Invoice" — the quarter — COMPLETE 2026-09-08

1. **`Decimal` for money before the first PDF exists.** Frozen invoice values
   must not be binary floats.
2. **Invoice as a frozen snapshot** (arbitration): `INV-YYYY-NNNN` allocated at
   issue, supplier and client as text blocks, per-day lines copied in,
   `timeZoneIdentifier` stamped, provenance carried as session UIDs. Locked
   means the app REFUSES day edits, deletion and retroactive rate changes on
   that period. Corrections go through void-and-reissue; the number is kept and
   never reused.
3. **`SchemaV1` + an empty migration plan, in its own commit, before the client
   entity.** Adopting versioning later is itself a migration event.
4. **Client + tax mode.** Under MWSTG Art. 27, stating a tax line while below
   the CHF 100k threshold means owing the tax stated — so the tax line must be
   structurally impossible when unregistered, not merely defaulted off.
5. **Swiss QR-bill to Implementation Guidelines v2.4** (in force 14 Nov 2026).
6. **Unbilled / invoiced / paid**, with the unbilled total in the panel.
7. **Adobe project names via Automation** — After Effects, Photoshop,
   Illustrator, InDesign, on activation only. Premiere never: its entire
   AppleScript dictionary is `capture` + `editoriginal`.
8. Adjusted hours appear on the invoice as a per-row marker AND one footnote.

## v1.5 "Day" — the timeline

Sessions on a strip: inspect, trim, split, reassign, every edit marked. It
replaces the edit-day sheet, not just the detail rows — per-session editing is
the honest unit. Domain is the working day, not 00:00–24:00. Typed adjustments
draw hatched at fixed width, because typed time has no span. This is the
Provenance test made visual, and why the reclaim prompt stays dead.

## Never

AI categorisation or AI-drafted timesheets · cloud sync, accounts, telemetry ·
Screen Recording · Pomodoro, focus scores, streaks · a second theme · a desktop
widget · calendar or Zapier integrations · per-project rounding rules · the
reclaim prompt · Mac App Store · subscriptions.

## Open decisions, owner only

1. **Apple Developer Program, $99/yr.** Ad-hoc signing means macOS 26 reports
   the app as damaged, and every rebuild drops the Accessibility grant. If
   Cutaway stays yours alone, skip it and fix the README's claims. If anyone
   else should install it, this is the blocker.
2. **Existing projects and InDesign.** New projects now pre-tick it. Your three
   existing projects still exclude it — tick it per project, or say the word and
   a one-time migration adds it to any project that already ticks another Adobe
   app.
3. **Rate advice.** Billing refused to model "you are underpricing". Should
   Cutaway ever answer *what should my rate be*, or only *what do I bill for
   this job*?
4. **The five junk `timex.store` backup folders** — delete, or leave.
