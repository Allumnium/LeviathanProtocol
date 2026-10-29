# Cargo state and arrival trade (steps 31–32)

`scripts/cargo_rules.gd` stores cargo separately from construction materials in
`economy.cargo = {version: 1, holds: {...}}`. Each hold uses the physical identity
`ship/<ship id>/unit/<unit index>` and records capacity (10), quantity, origin node,
grade and frozen unit value. Empty holds have no origin, grade or value. Snapshot
value is prospective income; registration and previews never change balances or
load goods. A separate physical copy starts empty.

Partial component damage does not change capacity or quantity. Destroying a hold
clears its contents; host destruction clears only the remaining loads. A zero-fee
`cargo_loss` ledger entry records quantity, origin, grade and unit value. The same
checkpoint commits damage, cargo, passenger casualties and accounting. A failed
write leaves live cargo and ledger unchanged for retry. Repeated checkpoints or
later host loss do not count the same goods twice. Repair restores empty space.

Checkpoint validation rejects malformed, over-capacity or unsettled destroyed
loads, forged hold identities and unknown state versions. Empty historical records
can outlive removed ships. Older checkpoints without a cargo namespace remain
compatible; no save-version migration is required. Loaded ships cannot be
dismantled, reserved or hidden by a revision change until their cargo is offloaded.

Cargo Holds are now buildable under Foundation. Inhabited secured arrivals sell
surviving loads at their stored origin price, then refill operational deployed
holds with destination goods for free. The first empty arrival only loads.
Basic/Uncommon/Rare values are 3/6/10 credits per unit. Partial loads sell their
actual quantity; destination prices never reprice goods already aboard.

Each physical load has a `cargo_sale` ledger identity based on its hold and origin
node. Arrival sales and `GameState.offload_cargo(ship_id)` consume the same load
through that ledger. Safe offload requires a secured inhabited location, sells
without refilling or changing passengers, and permits selecting one ship or all.
Repeated offloads, reloads, repairs and reopening a settled arrival never create
another sale/refill. Arrival sale, refill, passenger tickets/occupancy and location
persist in one atomic checkpoint; a failed write changes none of them.

Route previews use current stored cargo value and passenger ticket estimates.
Step 33 supplies the held-value display and explicit offload/discard UI. Step 18's
general-slot starter review, 300-credit target and opening playtest remain open.

Validation: `tests/test_cargo.gd` covers independent inventory, identity, seven
Basic Goods valued at 21, JSON/save reload, partial damage, destruction followed
by host loss, empty reconstruction, malformed records, loaded guards, failed writes
and retries. It uses isolated save paths and physical cargo fixtures, with real
campaign encounters/checkpoints for persistence checks. Step 31's 28 baseline suites passed, including 600
battle encounters, 1,000 graph seeds, 1,000 content seeds, three complete campaigns
and the UI interaction checks. Logs: `.local/step31/cargo.log`,
`.local/step31/baseline.log` and `.local/checks/1004f723571c41db8eb41fbd91d716ac/`.
The existing Windows certificate-store diagnostic and shutdown ObjectDB/resource
warnings remain separate from the zero-failure gameplay assertions.

`tests/test_cargo_arrivals.gd` adds sale-before-refill, seven Basic Goods paying 21,
frozen destination values, empty-first-arrival, inactive/destroyed capacity,
reconstruction, shared offload/arrival sale identities, real paid construction,
combined passenger/trade settlement, failed arrival/offload writes and reload checks.
Step 32 logs: `.local/step32/cargo-arrivals.log` and `.local/step32/baseline.log`.
All 29 step 32 baseline suites passed, including 600 battle encounters, 1,000 graph
seeds, 1,000 content seeds, three complete campaigns and UI interaction assertions.
Per-suite logs: `.local/checks/b2bdba7f49774cb193f230a622f4a053/`. Existing
certificate-store and shutdown diagnostics remain recorded separately.
