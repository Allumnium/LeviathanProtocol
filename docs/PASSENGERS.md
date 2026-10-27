# Passenger state and luxury

Step 28 adds aggregate passenger state and physical luxury rules through `PassengerRules`. Step 29 adds the secured-arrival transaction described below. Cabin, suite, Observation Deck, Grand Promenade and their research remain gated until passenger-loss handling also works in step 30.

| Accommodation | Places | Base luxury |
|---|---:|---:|
| Passenger Cabin | 4 | 1 |
| Luxury Suites | 4 | 2 |

Capacity is atomic: partial component damage preserves four places; destruction or host loss makes that capacity inoperable. Reconstruction restores empty space, never passengers. Physical reserve/role/family changes do not move or duplicate occupancy. Boarding policy will separately restrict arrivals to deployed operational hulls.

## Stable component state

The additive `economy.passengers` namespace has version 1 and a `components` dictionary keyed by `ship/<physical ship ID>/unit/<persistent unit index>`. Physical unit order is preserved by blueprint cloning, damage, reconstruction and checkpoint loading. Names, regular-family identity, formation, orientation and material positions do not identify passenger loads. A newly constructed copy receives a new physical ship ID and starts empty.

Each record stores only `ship_id`, `unit_index`, `equipment_id`, `capacity` (4), `occupied` (0–4), and `boarded_luxury` (1–3; suites at least 2). There are no individual passenger identities, destinations, contracts or bonds. Boarded luxury remains frozen for the load; the manifest separately derives current physical luxury. Destroying a luxury source does not rewrite historical boarding conditions.

`register_components` returns a detached economic-state copy with empty records for missing accommodation. It preserves existing loads, other economic domains and historical empty records. Repeated registration is idempotent. `snapshot` and `GameState.passenger_manifest()` are read-only: they expose stable ID, occupancy, available/operational capacity, current luxury and boarded luxury without changing persistent state.

Checkpoint validation accepts older saves without the namespace and preserves unrelated economic state. It rejects unknown versions, malformed fields, fractional/out-of-range counts, wrong capacities/luxury, mismatched IDs/types and non-accommodation units impersonating cabins. Occupied missing/destroyed accommodation or a dead host cannot silently disappear in a save: later loss transactions must explicitly clear those counts. Empty historical records may remain after hull removal. Historical ledger snapshots are not reinterpreted against today's fleet.

## Physical luxury sources

An operational Observation Deck adds one luxury to at most two orthogonally adjacent operational accommodation components, selected in stable physical component order. Multiple touching edges count once. Identical Deck sources do not stack. The source must touch the actual hull exterior; an enclosed courtyard or hole does not qualify. Exterior connectivity uses surviving occupied material, including loose cells, rather than decorative hull polygons. A damage-created opening can expose a Deck immediately. Clear row/column rays keep exterior searches local even for sparse hulls.

An operational Grand Promenade adds one luxury to accommodation anywhere on its own living host. Identical Promenades do not stack. Its bonus adds to Observation Deck, then final luxury clamps to 1–3. Crew does not affect luxury. Intact severed sections retain their actual adjacency; sources never benefit another hull. Source destruction removes current luxury immediately; reconstruction recomputes it without accumulating bonuses. Sanctuary and other future abilities remain gated.

## Verification and rollout

`tests/test_passengers.gd` uses detached physical-unit fixtures with the authoritative future recipes to test occupied accommodation while those recipes remain unavailable in live construction. It covers both four-place types, stable IDs/copies, JSON round trips, read-only/idempotent views, partial damage, destruction/empty reconstruction, source stacking and caps, two-recipient selection, host-only effects, rotation/reflection, enclosed holes and opened/sparse exteriors, frozen boarded luxury and malformed states. Real campaign checkpoints cover the additive empty namespace, older saves and rejection of fabricated occupied cabin references.

Step 28 changed files: `scripts/passenger_rules.gd` (and UID), `game_state.gd`, `run_checkpoint.gd`, `tests/test_passengers.gd` (and UID), `tests/run_baseline.ps1`, this document and the checklist/baseline index. No component readiness, research grant, starting fleet, price, income, loss fee or artwork changed in that step. Full regression results are recorded in TODO.md.

## Secured inhabited arrivals — step 29

`PassengerRules.boarding` builds a detached proposal: safely disembark existing survivors, then fill all operational accommodation on deployed physical ships. It evaluates current luxury for the new load and pays 8/12/16 credits per passenger at luxury 1/2/3. Four normal cabin places pay 32, suites normally pay 48, and four luxury-3 places pay 64. Partial damage retains all four places. Reserves, inactive regular families, unselected dedicated copies and destroyed accommodation cannot board. All surviving existing loads disembark safely, including any reserve load awaiting the later loaded-refit controls.

`ArrivalRules.apply` binds this proposal to the existing `run_id/arrival/node/<id>` ledger identity. The identity is checked before examining today's loadout. Once settled, reloading, reopening a port, changing luxury, repairing or constructing another cabin cannot create a different payout at that arrival. New accommodation remains empty until the next secured inhabited node. An uninhabited node changes neither occupancy nor ticket balance. Start and Last Light use the same inhabited-arrival rule; campaign node identity is unique on the forward-only route.

The arrival ledger records disembarked/boarded counts, ticket income and the participating component IDs/luxury. Occupancy, credits and deduplication are written in one checkpoint generation. Failed writes leave live state unchanged; recovery of a staged generation restores all three together. With no passenger state, arrival details and zero-payout fingerprints remain compatible with existing saves. Other economic domains are preserved for cargo's later sell-then-refill integration.

`GameState._secure_node` invokes arrival settlement after a successful approach and before port UI. It decodes staged physical accommodation rather than borrowing mutable live loadouts; ordinary no-accommodation campaigns retain the inexpensive compatibility path. `_apply_accounting` now applies the staged economic state alongside balances for both travel and combat-victory commits. Public arrival dispatch still requires a visited inhabited current node and no pending battle.

`tests/test_boarding.gd` covers 32/48/64-credit examples, first/next arrivals, safe disembarkation, reserves/families/dedicated copies, partial/dead capacity, new cabins waiting, frozen boarding luxury, uninhabited node classes, repeated dispatch/reload, staged-write interruption recovery and failed writes. Occupied future cabins use detached authoritative-recipe fixtures and an atomic-store domain validator; live campaign checks cover actual start/approach gates and economic-state application without exposing future components. No new UI or passenger construction is enabled in step 29. Step 30 must implement losses/debt before readiness changes.

Additional step 29 files: `scripts/arrival_rules.gd` (and UID), `passenger_rules.gd`, `game_state.gd`, `tests/test_boarding.gd` (and UID), `tests/run_baseline.ps1`, and related checklist/accounting/baseline docs.
