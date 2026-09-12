# PHARM — Pharmacy Cabinet

Part of **Mini-Hospital 2026**, a teaching hospital built for the course on
hospital, e-health and connected-medical-device informatics.

> Start here if you are new: the
> [course guide](https://github.com/LucaProcaryote/Dev_Central/blob/main/COURSE.md)
> explains how the six repositories fit together and contains the lab exercises.

A simulated automated dispensing cabinet: it holds the stock, controls the
drawers, and refuses to hand over a drug it should not.

## Run it

```bash
flutter pub get
flutter run -d chrome
```

It opens on a dispensing queue that already has work in it, cabinets that are
locked, and a stock list containing — deliberately — an empty slot, an expired
lot and several slots below their par level. Finding those is the first
exercise.

## What is in it

| Screen | What it does |
|---|---|
| **Dispensing queue** | Every dose due, built from the prescriptions rather than from a hand-kept list. Overdue doses are called out. Dispense or refuse, with a reason. |
| **Cabinet** | The wall of drawers. Lock and unlock the cabinet, open one drawer at a time, see stock, par level, lot and expiry per slot. Restock a slot. |
| **Stock** | Everything across all cabinets, filtered by default to what needs attention: empty, expired, expiring within 30 days, or below par. |

## The cabinet behaves like a cabinet

This is what makes it more than a stock table:

- It is **locked** until somebody with the right role unlocks it.
- **One drawer opens at a time.** Opening a second closes the first.
- The drawer **closes itself after eight seconds**, and says that it did —
  rather than silently leaving the state wrong.
- A **restock replaces the lot.** Topping a fresh lot into a drawer that still
  holds an expired one is precisely what an automated cabinet exists to
  prevent.

## The checks run before the drawer opens

The order is the lesson. A cabinet that lets you take the drug and *then* tells
you the patient is allergic to it has prevented nothing.

Blocking — the release is refused:

- the cabinet is locked
- the prescription is not active
- the slot is empty, or holds fewer units than were asked for
- the lot has expired
- the patient has a **high-risk** allergy to the product

Warning — the release proceeds only after an explicit, written acknowledgement:

- the patient has a **low-risk** allergy to the product
- the product is a controlled substance (which also requires a second name as
  witness; both names go on the record)

Advisory — stated, no acknowledgement needed:

- the lot expires within 30 days, so use it first

Allergy matching is by name across all three languages, plus beta-lactam
cross-reactivity read off the ATC code — so a penicillin allergy also flags
amoxicillin *and* ceftriaxone. It is deliberately simple and readable: a
production system would use a drug knowledge base with ingredient-level data.
That limitation is the point, and it is documented in
`packages/hospital_core/lib/src/clinical/safety_checks.dart` rather than hidden.

Every alert states its severity **in words** next to the colour.

## Languages

English, French and Dutch, switchable from the toolbar. Drug names, galenic
forms and allergy substances are translated in the database, not in the
interface strings — a francophone nurse sees *Pénicilline* on the allergy
banner without anything being translated on the fly.

## Configuration

| Define | Values | Default |
|---|---|---|
| `BACKEND` | `memory`, `restApi`, `dataConnect` | `memory` |
| `AUTH` | `demo`, `firebase` | `demo` |
| `API_BASE` | this application's API | `http://localhost:8083` |

## Tests

```bash
flutter test
```

Twenty-two tests. The interesting ones prove that the cabinet cannot be talked
into a bad release: a locked cabinet changes no stock, a high-risk allergy is
blocking rather than a warning, a cephalosporin trips a penicillin allergy, an
expired lot is refused, a controlled substance will not move without a witness,
and a low-risk allergy will not move without an acknowledgement. The drawer
auto-close is tested on a fake clock.

One bug these tests caught: the dispensing dialog builds on the root navigator,
which sits above the provider the application installs, so it could not see the
cabinet service and threw the moment anyone pressed *Dispense*. Fixed by
handing the service down explicitly.
