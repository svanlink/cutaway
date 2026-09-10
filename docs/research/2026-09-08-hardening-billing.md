# Hardening the invoice quarter: what an adversarial reader finds
*Billing department · 2026-09-08 · audit of HEAD 648d6aa. Nothing fixed, nothing committed.*

Method: read `Sources/Cutaway/Billing/*` and the six named test files; re-derived
every disputed figure in Swift 6 (`swiftc -O`, same `NSDecimalRound` / `NumberFormatter`
the app uses) and in Python `decimal` as a cross-check; re-verified the QR field table
against the SIX Implementation Guidelines PDF itself, not a summary.

Findings are stated as **input → number produced → number that should have been
produced → file:line**. Clean rows are reported as clean.

---

## A. Figures a client can dispute

### A1 — The same day is CHF 0.01 higher in the CSV than on the PDF. CRITICAL for credibility.

The 2026-09-07 report closed the `round2` / `format` split by pointing `NumberFormatter`
at `.halfDown`. It left a *second* pair of rounders that were never compared:

- `Money.round2(_:)` — `Money.swift:15-19` — floors the **Double** `value * 100`.
- `Money.rounded(_:currency:)` — `Money.swift:52-69` — floors the **Decimal** produced by
  `Money.decimal(_:places:6)`, i.e. by `String(format:"%.6f", value)`.

`%.6f` snaps binary noise back onto the exact decimal tie; multiplying the raw Double by
100 does not. Where the true product is an exact half-rappen and the Double lands a few
ulps above it, the two disagree — in opposite directions.

**Input:** CHF 90/h, one day of 14 553 s (4 h 02 min 33 s). Exact value 14553 × 90 ÷ 3600
= **363.825** — a true tie.

| Surface | Path | Prints |
|---|---|---|
| CSV `earned` / `total_earned` | `CSVExporter.swift:99` → `Money.round2` | `363.83` |
| Stats / invoice **string** | `BillingCurrency.format` | `CHF 363.83` |
| Invoice **line amount** (frozen Decimal) | `InvoiceBuilder.swift:42` → `Money.rounded` | `363.82` |

**Produced:** CSV 363.83, PDF 363.82.
**Should be:** 363.82 on both — it is a tie, and ties go to the client.
**Verified:** `Money.swift:15` vs `Money.swift:52`; consumed at `CSVExporter.swift:99`
and `InvoiceBuilder.swift:42`.

Frequency: over `4 h…9 h` of whole seconds, CHF 90/h produces **1 068** such days,
CHF 45/h **552**, CHF 150/h **154**. Rates that are multiples of 3 min of rate
(CHF 120/h, CHF 60/h) produce none — which is why the existing tests never saw it.
The CSV is the *higher* reading, so it also breaks under-billing bias.

`MoneyRoundingTests.testDecimalAndDoubleAgreeOnTheTieThatStartedThis:54` pins exactly
one point (3 610 s @ 45), where the two happen to agree. It is a point, not a property.

### A2 — Every time row on every invoice fails `hours × rate = amount`. HIGH likelihood noticed.

`quantity` is frozen at four decimal places (`InvoiceBuilder.swift:40`) and printed at two
(`InvoiceDocumentView.swift:193`). `unitPrice` is frozen at six (`:41`) and printed at two.
`amount` is computed from the *unrounded* seconds. So the three printed numbers on a row
are not related by multiplication.

**Input:** 8 h 40 min (31 200 s) at CHF 120/h.
**Produced on the page:** `8.67 h · 120.00 · CHF 1'040.00`.
**A client's arithmetic:** 8.67 × 120 = **CHF 1'040.40**. Gap CHF 0.40, unexplained.
**Should be:** either print hours at the precision they were frozen at, or print the
amount that the printed hours and rate produce. `InvoiceDocumentView.swift:108-112, 191-194`.

This is not an edge case. The 2026-09-07 report's own worked example fails on all eight
rows: `02.03 · 4.67 h · 120.00 · 559.90` (4.67 × 120 = 560.40, off by 0.50);
`04.03 · 5.94 h · 713.33` (712.80, off by 0.53). The report presented that table as the
correct output. Across a 20-day month the visible discrepancies sum to roughly CHF 5–8,
all in the client's favour, all arguable, all on the face of a document.

Worse where a day spans a rate change: `effectiveRate` is a blend
(`Models.swift:157-159`), so the Rate column prints e.g. `CHF 112.78` — a figure that
appears in no contract — with no note saying why.

### A3 — A day that is partly invoiced is billed again, in full. CRITICAL, largest money.

`issueInvoice` picks *sessions* correctly and then picks *totals* wrongly:

```
InvoiceStore.swift:76   sessions = billableSessions(...)          // unlocked only  ✓
InvoiceStore.swift:79-83 uidsByDay = [day: uids of those sessions] //              ✓
InvoiceStore.swift:84-85 days = dayTotals(for: project)            // ALL sessions  ✗
                              .filter { uidsByDay[$0.day] != nil }
```

`dayTotals` (`SessionStore.swift:364-377`) groups `project.sessions` with no
`isInvoiced` filter. A day survives the filter if it holds *one* unlocked session, and
then contributes *all* of its seconds.

**Input:** CHF 90/h. 4 April 09:00–11:00 (2 h) invoiced on INV-2026-0001 for CHF 180.00.
Later the same day, 14:00–15:00 (1 h) is recorded. Invoice April again.
**Produced:** line `Saturday 4 April · 3.00 h · 90.00 · CHF 270.00`.
**Should be:** `1.00 h · CHF 90.00`.
**Over-bills CHF 180.00 — work the client has already paid for, on a date they can see
twice.** `InvoiceStore.swift:84-85`; identical bug in the preview at `InvoiceSheet.swift:230`.

The panel disagrees with the document it is about to produce: `unbilledTotal`
(`InvoiceStore.swift:174-179`) filters per session and correctly says CHF 90.00.
`BillingStatusTests.testWorkAddedAfterIssuingStaysBillable:61` asserts that CHF 50.00 and
passes — it never issues the second invoice.
`InvoiceSnapshotTests.testWorkAlreadyInvoicedIsNeverBilledTwice:121` adds the new work on
day **5**, a fresh day, so it misses the case entirely.

### A4 — A budget is a ceiling per invoice, not per project. CRITICAL, second-largest money.

`budgetCapped` (`InvoiceBuilder.swift:75-90`) is handed `Money.decimal(project.budget)` —
the whole budget — on every issue (`InvoiceStore.swift:91-92`, `InvoiceSheet.swift:234`).
Nothing subtracts what previous invoices against the same project already billed.

**Input:** fixed budget CHF 4'500 at an internal CHF 120/h. Month 1: 48 h accrued → 5'760.
Month 2: 20 h → 2'400.
**Produced:** INV-…-0001 = CHF 4'500.00 (capped, correct). INV-…-0002 = CHF 2'400.00
(subtotal 2'400 < 4'500, so `guard` at `:76` returns uncapped). Lifetime **CHF 6'900.00**.
**Should be:** CHF 0.00 on the second invoice, and a line saying the budget is spent.
**Over-bills CHF 2'400 — 53 % above the agreed fixed price.**

`InvoiceSnapshotTests.testABudgetProjectBillsTheBudgetNotTheOverrun:158` issues once.

### A5 — A correction to an old day is stamped with today's rate. HIGH money, silent.

Invariant #4 of the 2026-09-07 report is still open. `setActiveSeconds` writes
`hourlyRate: project.hourlyRate` (`SessionStore.swift:298`); `addSession` writes
`let rate = project.hourlyRate` (`SessionStore.swift:125`).

**Input:** rate raised CHF 90 → CHF 120 on 1 Feb. On 5 March, 20 January is corrected from
6.0 h to 7.5 h.
**Produced:** the +1.5 h adjustment carries CHF 120. The day bills 6 × 90 + 1.5 × 120 =
**CHF 720.00**, and prints a blended rate of **CHF 96.00** for a January day.
**Should be:** 7.5 × 90 = **CHF 675.00** at CHF 90.00.
**Over-bills CHF 45.00 on one corrected day**, and prints a rate the January contract
never contained. `SessionStore.swift:298`, `:125`.

### A6 — COP: three surfaces, three numbers. MEDIUM, certain on every COP invoice.

`Money.minorUnits` is honoured by `Money.rounded` and by `BillingCurrency.format`.
It is **not** honoured by the CSV, which hard-codes `%.2f` on `earned`,
`hourly_rate`, `cumulative_earned`, `total_earned`, `budget` and `budget_remaining`
(`CSVExporter.swift:117-126, 138-139, 143`), nor by `format`'s zero-decimal branch, which
**floors** instead of rounding to nearest (`BillingEngine.swift:152`,
`amount.rounded(.down)`).

**Input:** COP 1'395'000.90 for one day.

| Surface | Prints | Path |
|---|---|---|
| CSV `earned` | `1395000.90` | `CSVExporter.swift:121` |
| `format` (screen, invoice) | `COP 1'395'000` | `BillingEngine.swift:152` — floor |
| `Money.rounded(·, .cop)` (frozen line) | `1395001` | `Money.swift:52` — ties down |

**Should be:** `1395001` everywhere; `format` is a full peso low and the CSV states
centavos that do not exist. `MoneyRoundingTests.testMinorUnitsFollowTheCurrency:72` tests
`Money.rounded` only and never the two surfaces that print.

### A7 — `Money.rounded` always rounds a negative away from zero. MEDIUM, latent.

`Money.swift:58` asserts "NSDecimalRound's `.down` is toward ZERO" and compensates at
`:64` with `floored -= 1`. Measured: `NSDecimalRound(Decimal(-12.3), .down)` returns
**−13** — it is already a floor. The compensation double-floors, after which
`scaled - floored` is always > 0.5, so the `> half` branch always fires and the function
returns the plain floor for *every* negative fraction, tie or not.

| Input | `Money.rounded` | `Money.round2` | Correct |
|---|---|---|---|
| −1260.001 | **−1260.01** | −1260.00 | −1260.00 |
| −500.004 | **−500.01** | −500.00 | −500.00 |
| −12.344 | **−12.35** | −12.34 | −12.34 |
| −45.125 (tie) | −45.13 | −45.13 | −45.13 |

`Money.swift:49-51` claims the two are "the same rule and the same direction". They are
not. `MoneyRoundingTests` and `DecimalMoneyTests` each test exactly one negative — the
tie, the one value the bug gets right.

Not reachable from a time line today (rates are non-negative), so: latent. It becomes live
the day `InvoiceLineKind.deposit` gets a UI, which is what the enum exists for
(`Invoice.swift:11`). A CHF 500.00 deposit will print as **CHF −500.01**.

`BillingCurrency.format` disagrees again on negatives: `format(-0.125)` = `-0.12`
(`.halfDown` on a `NumberFormatter` is toward zero), while both `Money` functions give
`-0.13`. The comment at `BillingEngine.swift:148-150` — "Match `Money.round2` exactly" —
is true for positives only.

### A8 — CSV and PDF state a different period and a different budget position. MEDIUM.

- `CSVExporter.swift:135-136` writes `period_start` / `period_end` as the first and last
  **worked** day. The PDF writes the requested span (`InvoiceDocumentView.swift:78-82`).
  A March with no work before the 5th: CSV says `2026-03-05`, PDF says "Work from 1 Mar to
  31 Mar". Two statements of the supply period on two documents about one job.
- `CSVExporter.swift:105, 143` print `budget_remaining` negative on an overrun
  (−1'260.00), while the invoice caps at the budget and shows the overrun as an
  adjustment line. Same period, two positions. The 2026-09-07 report ruled the overrun is
  printed as "not billed" — the CSV prints it as a deficit.
- The CSV includes days that are **already invoiced** (it draws on `dayTotals`), so a CSV
  attached to an invoice restates work billed on an earlier one.

### A9 — Clean rows in this section

- **A day spanning a rate change** reconciles inside the model: `earned` is carried per
  session at its stamped rate and `effectiveRate = earned / hours`
  (`Models.swift:157-159`), so `hours × effectiveRate == earned` exactly. The blend is
  correct; only its *printing* (A2) is not.
- **`record` stamps the rate at the time of work** (`SessionStore.swift:95`) and
  `InvoiceSnapshotTests.testAnIssuedTotalSurvivesARateChange:37` genuinely pins that a
  raise does not reprice a frozen document. Verified.
- **Round-once-then-sum** holds inside each surface: `Money.total` sums already-rounded
  parts (`Money.swift:72-74`), `CSVExporter` accumulates rounded rows
  (`CSVExporter.swift:101-102`). The subtotal is the sum of the printed lines. Clean.
- **`Money.amount` multiplies before dividing** (`Money.swift:41-47`) — the comment is
  right and the behaviour is right: 3 610 × 45 ÷ 3600 arrives as exactly 45.125.
- **Budget-cap VAT proration** (`InvoiceBuilder.swift:86-87`) recomputes tax as
  `cap × tax ÷ subtotal` rather than `cap × rate ÷ 100`. Scanned 228 572 combinations:
  282 disagree (0.12 %), always by exactly CHF 0.01, e.g. budget 7'250.50 against a
  subtotal of 7'253.03 prints **587.30** where 8.1 % of 7'250.50 is **587.29**. Real but
  tiny; noted rather than ranked, except that it over-states tax (see B4).
- **CSV formula-injection guard and POSIX locale pinning** (`CSVExporter.swift:73-88,
  154-164`) are correct and byte-stable. Clean.
- **`InvoicePeriod` half-open intervals** and the inclusive conversion at
  `InvoiceSheet.swift:140-146` are consistent; `billableSessions` compares
  `startOfDay` on both ends (`InvoiceStore.swift:39-46`). No off-by-one at the period
  boundary. Clean.
- **A running timer is excluded**: the invoice path uses `dayTotals`, not
  `AppModel.dayTotalsIncludingLive:511`. Clean.

---

## B. The printed page under MWSTG

### B1 — Any owner can print a tax they do not owe. CRITICAL legal.

`TaxMode.issueRefusal` (`TaxMode.swift:46-55`) admits a Swiss VAT invoice on one
condition: `supplierVATNumber` is not the empty string after trimming. There is no
registration flag, no `CHE-` format check, no mod-11 check digit, no confirmation step,
and no turnover monitoring anywhere in the codebase (`grep` for `100_000` and `100000`
returns nothing).

**Input:** an unregistered owner selects "Swiss VAT 8.1 %" in the picker
(`InvoiceSheet.swift:90`) and types `x` in the UID field.
**Produced:** a page carrying `UID x`, `VAT 8.1 % · CHF 503.12`, and
"Swiss VAT at 8.1 %."
**Should be:** refused. MWSTG Art. 27 para. 2 — a person not entered in the register who
states a tax **owes the tax stated** unless the invoice is corrected.

`TaxMode.swift:7-10` says this is "enforced in `canIssue`, not left to a checkbox". There
is no `canIssue`, and the enforcement is a non-empty string. The 2026-09-07 report
demanded "Cutaway must make a tax line impossible while `registered == false`"; there is
no `registered` anywhere in the model.

Fedlex SR 641.20 Art. 27, re-verified path: <https://www.fedlex.admin.ch/eli/cc/2009/615/en>.

### B2 — A registered supplier prints a UID that is not a VAT number. MEDIUM legal.

`Supplier.block` (`Supplier.swift:28`) prints `UID CHE-123.456.789`. MWSTG Art. 26 para. 2
let. a requires the number **under which the supplier is entered in the VAT register** —
which is the UID carried in its VAT form, `CHE-123.456.789 MWST` (TVA / IVA). The suffix
is what distinguishes an enterprise identification number from a VAT registration.
**Produced:** `UID CHE-123.456.789`. **Should be:** `CHE-123.456.789 MWST`.

### B3 — The page can go out with no recipient address at all. MEDIUM legal.

`InvoiceSheet.issue()` (`:240-262`) checks `supplier.missingForInvoice` and
`taxMode.issueRefusal`. Neither looks at the client. `Project.clientBlock`
(`Models.swift:56-60`) drops empty parts, so a project with a name and no address yields a
one-line block. `issueInvoice` accepts any `clientBlock`, including `""`.
**Produced:** an invoice whose "Billed to" is `Aurora EC` and nothing else — which is
precisely what `InvoiceSnapshotTests` issues throughout.
**Should be:** refused. Art. 26 para. 2 let. b requires the recipient's name **and
location**.

Related and weaker: Art. 26 para. 2 let. d requires the *nature and object* of the
supply. The page carries a date, a quantity in hours and a project name
(`InvoiceDocumentView.swift:69-73, 97-117`). There is no field anywhere for what the work
*was* — no "Video editing, 4× 30 s cutdowns". A day row reading "Wednesday 4 September"
states extent, not nature.

### B4 — The note and the tax row can print two different rates on one page. MEDIUM.

`invoice.taxRate` is frozen at issue (`Invoice.swift:41`, written `InvoiceStore.swift:107`)
and drives the row (`InvoiceDocumentView.swift:125`). `TaxMode.note`
(`TaxMode.swift:36`) interpolates `Self.swissStandardRate` — the **current constant**,
read live at `InvoiceDocumentView.swift:145`.
**Input:** invoice issued at 8.1 %; the ESTV standard rate later moves to 8.5 % and the
constant at `TaxMode.swift:23` is updated; the owner re-prints the old PDF.
**Produced:** row `VAT 8.1 % · CHF 503.12` above a note reading "Swiss VAT at 8.5 %."
**Should be:** 8.1 % in both. The snapshot has a live leak.

The same class of leak: `TaxMode.note` for `notRegistered` (`TaxMode.swift:34`) asserts
"below the CHF 100'000 threshold" — a claim about turnover the app never measures and
that becomes false the year the owner crosses it, printed on every invoice.

### B5 — A non-registered supplier cannot issue an EU reverse-charge invoice. MEDIUM.

`TaxMode.swift:50-51` refuses `euReverseCharge` unless the *supplier's* UID is non-empty.
A Swiss freelancer below the threshold has no UID, and the correct invoice for an EU
business customer is exactly one with the words "Reverse charge", the **customer's** VAT
identification number, and no supplier VAT number. The app refuses it and leaves only
"Outside scope", which prints nothing (`TaxMode.swift:40`).

Symmetrically, nothing requires the **client's** VAT ID on a reverse-charge invoice —
`Project.clientBlock` simply omits it when empty (`Models.swift:57`). Directive
2006/112/EC Art. 226 (4) requires it; Art. 226 (11a) requires the words.

### B6 — Clean rows in this section

- **No path prints a tax line unless `taxMode == .swissVAT`.** `showsTaxLine`
  (`TaxMode.swift:28`) is the single gate; `InvoiceBuilder.totals:61` sets tax to `0`
  otherwise and `InvoiceDocumentView.swift:124` hides the row. `notRegistered`,
  `euReverseCharge` and `none` cannot produce a tax amount, a rate, or a "0 % VAT" line.
  The Art. 27 *shape* is right; only the gate on entering `swissVAT` is missing (B1).
- **The reverse-charge wording is the literal wording.** "Reverse charge — VAT to be
  accounted for by the recipient." (`TaxMode.swift:38`) contains the required phrase.
- **`TaxMode.none` prints nothing.** A USD or COP invoice carries no VAT statement and no
  mention. Correct.
- **No CHF 0.05 rounding anywhere.** `grep` confirms it: nothing rounds to five rappen,
  so the printed total and the QR amount cannot disagree. The 2026-09-07 overrule of the
  predecessor report is correctly implemented — a genuinely clean row.
- **A refused issue locks nothing.** `issueInvoice` throws before the first write
  (`InvoiceStore.swift:58-75`) and pins the session lock to the last statement before
  `save()` (`:135`). `testSwissVATIsRefusedWithoutAUID:171` checks it. Clean.
- **VOID prints VOID** in red at `InvoiceDocumentView.swift:49-51`, and a voided invoice
  cannot be re-saved as a PDF (`InvoiceSheet.swift:163`). Clean.

---

## C. The QR-bill payload, field by field

Checked against the SIX *Implementation Guidelines QR-bill*, v2.3 PDF, fetched and read
this session (<https://www.six-group.com/dam/download/banking-services/standardization/qr-bill/ig-qr-bill-v2.3-en.pdf>);
v2.4 confirmed to change nothing for CHF and to restrict EUR to IBAN/SCOR and
IBAN/unstructured.

### C1 — Structure and positions: clean.

`SwissQRBill.payload` (`:113-123`) emits, in order: 3 header · 1 IBAN · 7 creditor ·
7 empty ultimate-creditor · 2 amount+currency · 7 debtor · 2 reference · 1 message ·
`EPD`. **31 lines, CRLF-separated.** That is the specification's order and count. The
seven reserved ultimate-creditor lines are present and empty; an absent debtor still
occupies its seven lines (`:119`), pinned by
`SwissQRBillTests.testAnAbsentDebtorStillOccupiesItsLines:84`. Amount at index 18,
currency at 19, trailer last — pinned at `:36-46`. No off-by-one. Clean.

Reference/IBAN pairing is enforced in both directions (`:106-111`): QRR demands a QR-IBAN,
anything else refuses one. `isQRIBAN` reads the IID at positions 5–9 against 30000–31999
(`:83-87`). Correct. `issueInvoice` refuses a QR-IBAN outright with a reason rather than
inventing a 27-digit reference it cannot compute (`InvoiceStore.swift:68-74`) — the right
call. Clean.

`creditorReference` (`:139-156`) is ISO 11649 and verified independently: `INV-2026-0007`
→ **`RF48INV20260007`**, `INV-2026-0001` → **`RF16INV20260001`**, both passing mod-97-10
round-trip. Clean.

> Note for the record: the 2026-09-07 report's worked example gives `RF63 20260007` for
> the same invoice number. That reference is not what the code produces and does not
> validate against this body — the report drops the `INV` letters, the code keeps them.
> The code is right; the report cannot be used to check it.

### C2 — Every QR-bill the app actually prints violates three mandatory address fields. CRITICAL.

`SwissQRBillTests` builds a well-formed `Address` with `postalCode: "8004", town: "Zürich"`
(`SwissQRBillTests.swift:11-14`). The **only production caller** does not:

```
InvoiceDocumentView.swift:162-169
  creditor = Address(name: line(supplierBlock, 0),
                     street: "", buildingNumber: "",
                     postalCode: "",  town: line(supplierBlock, 1),
                     country: "CH")
```

**Input:** `supplierBlock` = `"Sebastian van Eickelen\nBahnhofstrasse 12\n8001 Zürich\nUID CHE-123.456.789"`.

| Field | Emitted | Required | Spec |
|---|---|---|---|
| AdrTp | `S` | `S` | ok |
| Name | `Sebastian van Eickelen` | ≤ 70 | ok |
| StrtNmOrAdrLine1 | *(empty)* | **mandatory**, ≤ 70 | **violated** |
| BldgNbOrAdrLine2 | *(empty)* | optional | ok |
| PstCd | *(empty)* | **mandatory**, ≤ 16 | **violated** |
| TwnNm | `Bahnhofstrasse 12` | **mandatory**, ≤ 35 — the *town* | **wrong value** |
| Ctry | `CH` | mandatory | ok |

**Should be:** `S · Sebastian van Eickelen · Bahnhofstrasse · 12 · 8001 · Zürich · CH`.

The payload declares a structured address and then omits the two fields that make it
structured. A validating bank rejects it; a lenient one books a payment against a
creditor whose town is a street. `line(block, 1)` is whatever the owner typed on line
two — for a one-line address it is `UID CHE-123.456.789` in the town field.

The debtor block has the same defect **plus a hard-coded `country: "CH"`**
(`:169`), so a German client on an EUR reverse-charge invoice — a combination the app
explicitly permits (`SwissQRBill.assertSupported:47-51` allows EUR) — is declared Swiss.

No test covers `InvoiceDocumentView.qrPayload`. `InvoicePDFTests.testThePaymentPartReachesThePage:188`
checks that a payment part appears, not what is in it. The QR suite tests a payload
the app never constructs.

### C3 — `try?` discards the refusal. MEDIUM.

`InvoiceDocumentView.swift:170` swallows every `SwissQRBill.Refusal`. If the payload
cannot be built the payment part silently vanishes and the owner is told nothing; the
client receives an invoice with no way to pay it. Fail-safe in direction, silent in
practice.

### C4 — A zero or negative total produces an out-of-range amount. LOW, latent.

The spec fixes the amount at 0.01 … 999 999 999.99. `amountString(Decimal(0))` returns
`"0.00"` (`SwissQRBill.swift:127-135`), and `SwissQRBillTests.swift:47` **pins that as
correct**. Not reachable today (`nothingToBill` blocks an empty invoice), but the same
function will happily render `-500.00` once a deposit line exists. No length validation on
Name / StrtNm / PstCd / TwnNm either, and no character-set check against the spec's
Latin subset.

### C5 — Printed amount format. LOW.

`PaymentPartView.swift:44, 63` prints the amount with `SwissQRBill.amountString`, i.e.
`6714.51` with no separator. The spec asks for the *printed* amount to be grouped —
`6 714.51`. Cosmetic, but the payment part is the half of the page a bank clerk reads.

---

## D. The frozen snapshot

### D1 — An invoice and the store can diverge, and nothing can detect it. CRITICAL.

`assertNothingInvoiced` exists (`SessionStore.swift:63-66`) and is called by **no
production code** — only by two tests (`ProjectDelete.swift:22`,
`InvoiceSnapshotTests.swift:154`). `SessionStore.delete(_:reassignTo:)`
(`SessionStore.swift:81-88`) deletes the project unguarded, cascading away every
`WorkSession` while the `Invoice` rows survive with `sessionUIDs` pointing at nothing.

**Input:** issue INV-2026-0004, then delete the project.
**Produced:** an issued invoice whose every line traces to sessions that no longer exist.
**Should be:** refused by number, per the 2026-09-07 arbitration §2.

The arbitration justified `sessionUIDs` on the grounds that they "let the app *detect* the
divergence". Nothing reads them. `grep sessionUIDs Sources/` returns only the write path
(`InvoiceStore.swift:129`) and the model. There is no reconciliation function, no
verification command, no badge. `testEveryLineTracesToItsSessions:91` performs the check
the app cannot perform for itself.

`SessionStore.restore(_:for:)` (`:~255-265`) deletes and re-inserts a day's sessions from
a `DayEdit`, which carries no `uid` and no `invoiceNumber`. An undo therefore destroys
provenance and silently unlocks. It has no lock guard of its own.

### D2 — Rate and currency can be changed out from under an issued invoice. HIGH.

`ProjectsModel.update` (`:210-227`) writes `hourlyRate` and `currency` through
`store.update` (`SessionStore.swift:74-77`), which is a bare `mutate` + `save`. No lock
check. The arbitration §2/§4: "Refuse: any rate edit that would reprice locked work" and
"Changing a project's currency: refused outright once any session is locked."

The frozen invoice survives (`Invoice.swift` stores strings — good). What does not survive
is **legacy sessions with `hourlyRate == 0`**, which fall back to `project.hourlyRate` at
read time (`Models.swift:142`).
**Input:** legacy sessions billed at CHF 90 on INV-2026-0003; the owner raises the project
to CHF 120.
**Produced:** the PDF still says CHF 90.00 (frozen). The CSV and Stats for the identical
period now say **CHF 120.00**. Same period, two documents, two rates, no warning.
Currency is worse: switch CHF → EUR and every historical figure is re-labelled.

### D3 — Issued before printed; a normal month cannot be printed at all. HIGH.

`InvoiceSheet.issue()` calls `issueInvoice` (`:253-258`) — which allocates the number and
locks every session — and only then opens the save panel and calls `InvoicePDF.write`
(`:268-280`). `write` refuses more than **16 lines** when a payment part is present
(`InvoicePDF.swift:20, 26-28`).

**Input:** an ordinary month — 20 worked days — with an IBAN configured.
**Produced:** INV-2026-0007 is issued, 20 days of work are locked, and the PDF throws
"This period has 20 lines — more than one page holds". The owner has a numbered, locked
invoice and no document. The only escape is void-and-reissue, which spends a number and
still cannot print.
**Should be:** the line-count check runs *before* the number is allocated.

`InvoicePDFTests.testTooManyLinesRefusesRatherThanCropping:97` issues the invoice, asserts
the render throws, and never checks that nothing was issued — the failure mode is pinned
as correct behaviour. The 16-line ceiling makes the payment part unusable for the app's
main use case, which is billing a month.

### D4 — The printed period drifts by a day in another time zone. HIGH, certain.

`Invoice.timeZoneIdentifier` is stored (`Invoice.swift:52`, written
`InvoiceStore.swift:114`) and **never read by the renderer**. `periodLine`
(`InvoiceDocumentView.swift:78-82`) and `dateLine` (`:58-61`) call
`Date.formatted(.dateTime…)` with no `timeZone`, so they resolve in the machine's current
zone.

**Input:** invoice issued in Zurich for March 2026. `periodStart` is
`startOfDay(1 Mar)` = `2026-03-01T00:00+01:00`. Owner travels; the Mac is set to
`America/Bogota`.
**Produced:** "Work from **28 Feb** to 30 Mar 2026" — the frozen instant re-read five
hours west.
**Should be:** "Work from 1 Mar to 31 Mar 2026", rendered in `Europe/Zurich`.

The amounts and the day labels *are* safe: `InvoiceLine.text` is frozen as a string at
issue (`InvoiceBuilder.swift:92-97`). Only the period header, the issue date and the due
date move — which is the one Art. 26 field the movement affects.

`testTheIssuedTotalIsTimeZoneIndependent:52` constructs a `bogota` calendar at `:61-62`
and **never uses it**. The two assertions after it are byte-identical to the two before.
The test cannot fail.

### D5 — `adjustedHours` reaches the page. Clean, with one hole.

- Frozen per line (`InvoiceBuilder.swift:50`), persisted (`InvoiceStore.swift:128`),
  summed on the model (`Invoice.swift:85-87`), printed twice: a dagger on the row it
  belongs to (`InvoiceDocumentView.swift:103-105`) and a footnote below the totals when
  the sum is positive (`:147-151`). The CSV keeps the per-day column
  (`CSVExporter.swift:118`). Typed time is visibly distinct all the way onto the invoice,
  through every path that builds a line. Verified clean.
- The hole is upstream and is invariant #7 of the 2026-09-07 report, still open: the
  **shrink** branch of `setActiveSeconds` trims existing tracked sessions without setting
  `isAdjusted`, so a hand-corrected day that was reduced reports `adjusted_hours 0.00` and
  gets no dagger. Benign for the client, corrosive for the record.
- `InvoiceSheet.refresh():228` reads `s.uid` without `ensureUID()`, so a preview's
  provenance is a list of empty strings. Harmless — the preview is discarded — but it
  means the preview and the issued document are not built from identical inputs, which is
  what `:221-222` claims.

### D6 — A voided number cannot be reused. Clean.

`nextNumber` (`InvoiceBuilder.swift:104-112`) takes `max + 1` over every existing number
with the year prefix, and `invoices()` (`InvoiceStore.swift:29-31`) fetches all statuses.
`voidInvoice` (`:146-156`) keeps `number` and only clears the session locks. There is no
delete path for an `Invoice` anywhere in `Sources/`. Pinned by
`testAReissueNeverReusesAVoidedNumber:80`. Verified clean.

Two lesser notes: `nextNumber` derives the year from `now`, not from the period, so an
invoice raised in January for December work numbers into the new year — conventional and
correct. And `InvoiceStore.markPaid(_:on:)` (`:158-162`) accepts an `on date:` parameter
and never stores it: the payment date is not recorded anywhere.

`InvoiceSheet.issued` (`:151-154`) matches invoices by `projectName ==`, so renaming a
project (`SessionStore.rename:68-71`, itself unguarded) hides every past invoice for it,
and two projects sharing a name commingle theirs.

---

## E. Every invariant that must be pinned by a test

Carried forward from the 2026-09-07 list, with what this audit adds. The ones marked
**open** have no test today, or have a test that cannot fail.

1. **open** — `Money.round2(x)` and `Money.rounded(Money.decimal(x), .chf)` agree for every
   `(seconds, rate)` over a swept grid, not at one point. Counterexample: 14 553 s @ 90.
2. **open** — `format(Money.rounded(x, c))` renders the same digits as `Money.rounded`
   itself, for all four currencies. Counterexample: COP.
3. **open** — for every line, `format(quantity) × format(unitPrice)` reconciles with
   `format(amount)` to the currency's minor unit, or the page does not print all three.
4. **open** — a day carrying one locked and one unlocked session bills only the unlocked
   seconds.
5. **open** — Σ of every non-void invoice for a budget project never exceeds the budget,
   across any number of issues.
6. **open** — an adjustment to day *D* carries the rate in force on *D*.
7. **open** — a hand-shrunk day is flagged `isAdjusted`.
8. **open** — `Money.rounded` on a negative rounds to nearest, ties away from zero;
   assert −1260.001 → −1260.00 and −500.004 → −500.00, not only the tie.
9. **open** — the rendered `periodLine`, `dateLine` and every date string come out
   byte-identical under `Europe/Zurich` and `America/Bogota`. The current test must
   actually *use* the second calendar.
10. **open** — the payload built by `InvoiceDocumentView.qrPayload` (not by a hand-made
    `Address`) has a non-empty `PstCd` and a `TwnNm` that is a town, for a realistic
    supplier block; and the debtor country is not hard-coded.
11. **open** — no `.swissVAT` invoice can be issued without a `CHE-` formatted,
    check-digit-valid UID and an explicit registration fact on the supplier.
12. **open** — an invoice cannot be issued without a recipient location.
13. **open** — a failed `InvoicePDF.write` leaves no invoice issued and no session locked.
14. **open** — deleting a project with invoiced sessions is refused by number; so is a
    rate or currency change.
15. **open** — a reconciliation function exists that reads `sessionUIDs` and reports a
    drifted document. Today the property is only checkable from a test.
16. **open** — CSV `total_earned` for a period equals the invoice subtotal for the same
    period, on the same days, in every currency.
17. **held** — a raise does not reprice a frozen document (`:37`).
18. **held** — void keeps the number, releases the work, and the number is never reused
    (`:67`, `:80`).
19. **held** — no mode but `.swissVAT` can produce a tax amount (`:184`, `:195`).
20. **held** — the QR payload's field order and reference/IBAN pairing
    (`SwissQRBillTests:19, 36, 66, 84`) — for the payload shape, though not for the
    payload the app builds.
21. **held** — `adjustedHours` reaches the frozen document and the page (`:113`,
    `InvoicePDFTests:58`).

---

## F. Ranked

By money at risk × the chance a client, bookkeeper or inspector sees it.

| # | Finding | Money | Seen? | Where |
|---|---|---|---|---|
| 1 | Partly-invoiced day re-billed in full (A3) | +100 % of a day, repeatedly | certain — the date appears on two invoices | `InvoiceStore.swift:84-85` |
| 2 | Budget cap is per invoice, not per project (A4) | +CHF 2'400 on a CHF 4'500 job | certain — the client holds the contract | `InvoiceBuilder.swift:75-76` |
| 3 | Every QR-bill omits mandatory PstCd / StrtNm and puts a street in TwnNm (C2) | payment fails | certain — the bank | `InvoiceDocumentView.swift:162-169` |
| 4 | `hours × rate ≠ amount` on every row (A2) | CHF 0.40/row | very likely — one multiplication | `InvoiceDocumentView.swift:108-112` |
| 5 | Unregistered supplier can print VAT (B1) | the whole tax, owed under Art. 27 | on audit | `TaxMode.swift:46-55` |
| 6 | Issued before printed; 16-line ceiling (D3) | a numbered invoice that cannot exist | first real month | `InvoiceSheet.swift:253` |
| 7 | Corrections stamped at today's rate (A5) | +CHF 45/day | if they check the rate | `SessionStore.swift:298, 125` |
| 8 | Project delete / rate / currency unguarded, no reconciliation (D1, D2) | unbounded | only after the fact | `SessionStore.swift:81`, `ProjectsModel.swift:214` |
| 9 | Printed period shifts a day abroad (D4) | none | certain, after travel | `InvoiceDocumentView.swift:78-82` |
| 10 | CSV and PDF disagree by CHF 0.01 on a tie (A1) | CHF 0.01 | if both are sent | `Money.swift:15` vs `:52` |
| 11 | COP floors on screen, prints centavos in the CSV (A6) | COP 1 | every COP invoice | `BillingEngine.swift:152`, `CSVExporter.swift:121` |
| 12 | No recipient location; no description of the work (B3) | none | on audit | `InvoiceSheet.swift:240` |
| 13 | `Money.rounded` floors every negative (A7) | CHF 0.01, latent | when deposits ship | `Money.swift:64` |
| 14 | Note prints the live VAT rate, not the frozen one (B4) | none | on a reprint after a rate change | `TaxMode.swift:36` |
| 15 | CSV period and budget position differ from the PDF (A8) | none | if both are sent | `CSVExporter.swift:135, 143` |
| 16 | Reverse charge blocked without a UID; client VAT ID not required (B5) | none | EU client's accountant | `TaxMode.swift:50` |
| 17 | Payment date discarded; invoices matched by project name (D6) | none | reconciliation | `InvoiceStore.swift:158` |

Clean and worth stating: the QR payload's **structure** — 31 lines, CRLF, the seven
reserved lines, amount at 18 and currency at 19, reference/IBAN pairing both ways, the
ISO 11649 check digits, the refusal to invent a QR reference. Round-once-then-sum inside
each surface. `Money.amount` multiplying before dividing. Rate stamping at `record`.
Void semantics and gapless numbering. `adjustedHours` on every path that builds a line.
No five-rappen rounding anywhere. The formula-injection guard and the POSIX-pinned CSV.
