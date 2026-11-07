# Resolved development thoughts

Resolved entries moved from [THOUGHTS.md](THOUGHTS.md), preserving their context and outcomes. This is a reference, not an active backlog or authorization to change gameplay. Open follow-ups remain in THOUGHTS.md or [TODO.md](TODO.md).

## 2026-11-07 - Starter package ownership

- **Original question (2026-11-07):** Keep engine-wide equipment and fleet packages in core, but put the current campaign's selected starter package and resources in leviathan. This lets another scenario reuse the mechanics without inheriting the convoy charter. P2 can introduce a small start definition now; P6 can compose it into scenario recipes.
- **Resolved 2026-11-07:** Added `core:convoy` as a reusable fitted fleet package and `leviathan:charter` as the campaign's starting resources and dock. No new player setup controls are needed for this phase; P6 can expose starts through scenario recipes.

## 2026-11-07 - Cached content views

- **Original refactor opportunity (2026-11-07):** GameDefinitions, SlotCatalog and ShipLoadouts keep independent static caches. When the editor reloads a pack, those caches can retain previous definitions. Tie cache lifetime to the loaded database or remove the duplicate caches as callers move to Content.
- **Resolved 2026-11-07:** GameDefinitions, SlotCatalog and ShipLoadouts now invalidate their caches when the loaded DefDatabase changes. A patch-only integration check warms the original views, replaces content, verifies patched reads and restores the original database. The remaining UI/static-cache audit stays open in THOUGHTS.md.

## 2026-11-07 - Frozen fares

- **Resolved observation (2026-11-07):** Cargo and passenger loads keep their departure unit value. Validation must allow a valid stored fare that differs from today's economy definition; otherwise changing a fare could invalidate an occupied ship.
- **Resolution 2026-11-07:** P2 starter/economy validation accepts bounded positive stored fares and tests that they survive a change in current economy definitions. P3 content snapshots remain planned in TODO.md.

## 2026-11-07 - Active-suite stale fixtures

- **Original concern (2026-11-07):** Four focused suites have documented failures from before P1. Distinguish stale fixtures from gameplay defects before using them to assess refactors; otherwise a new regression could hide inside an accepted failure count.
- **Resolved active portion 2026-11-07:** The three recorded active-suite failures came from old formation coordinates, Map/Fleet expectations, former lab output and fixed-speed assumptions. The ammunition suite also still expected three alien missiles and admitted a post-incident event without its required story flags. Fixtures were corrected while preserving their transaction and gameplay assertions; flagship selection 307, research travel 260, expedition events 90 and fleet missiles 118 checks passed with zero failures. Legacy archive-suite retirement remains open in THOUGHTS.md and TODO.md.

## 2026-11-07 - Frozen setup fixture

- **Original observation (2026-11-07):** The ammunition UI fixture changed simulation supply after the deployment screen had rendered, then expected the combat-only refresh to run during frozen setup. Establish empty supply before admission so the fixture tests the actual saved-supply path; hidden setup speed controls should not count as visible overlap.
- **Resolved 2026-11-07:** The fixture now establishes empty saved supply before admission and checks visible controls for overlap. The focused fleet-missile suite passed 118 checks with zero failures without changing gameplay.
