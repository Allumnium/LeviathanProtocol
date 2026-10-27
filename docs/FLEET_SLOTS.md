# Fleet families, dedicated slots and reserves

Step 17 applies the new roster policy to active campaigns. Historical legacy-layout saves keep their compatibility behavior; normal new runs use the policy.

## Stable families and physical ownership

Three regular slots contain stable run-scoped family IDs. Each family registers blueprint fingerprints and a current blueprint snapshot. Physical ships retain their own ID, blueprint, component HP, family ID and reserve flag. Display names do not determine eligibility or deployment.

Fingerprinting ignores blueprint insertion order and translation. Renamed/imported copies of a registered blueprint remain in the same family. Direct/editor and library construction both reject an unassigned fourth active family before consuming resources or creating an identity. Explicit editor revisions register under the selected family; existing physical copies keep their old blueprints and HP. Construction of a revised design still consumes its normal materials/credits.

At a secured port, choosing a new family replaces that slot's active ID. Existing ships of the old family remain owned reserves. Changing a slot does not refit, heal or refund them. Individual copies may also be reserved/restored. The Fleet panel shows five scrollable design slots and separate owned/deployed counts with reserve controls. Reserve previews are dimmed on the formation board.

## Dedicated eligibility

`FleetRules` validates loadouts independently of names and archived metadata:

- Every hull has exactly one Command Center.
- Science requires exactly one Research Lab and forbids Cargo Holds and passenger berths.
- Civic requires a Cargo Hold, Passenger Cabin or Luxury Suites and forbids labs. Observation Deck/Grand Promenade alone provide no berths and do not qualify.
- Both dedicated roles allow at most six Offense material tiles, including loose tiles. Neither permits mining hardware, strike-craft bays or offensive capstones.
- Other legally researched equipment remains available on regular hulls, including mining and mixed support equipment.

Each dedicated role references at most one physical ship ID. Extra owned support hulls remain reserves. Deployment rechecks the actual physical loadout and requires its lab/cargo/accommodation to be operational; names cannot grant a role or bypass destroyed equipment. Current-run research/implementation checks still apply. Lab I is now functional; accommodation and Cargo Holds remain gated. Starter support hulls and their equipment arrive in their scheduled milestones.

Default support movement is Escort: follow a selected regular hull (or the nearest living regular hull), remain behind it and fire only at targets within weapon range. Supports do not automatically pursue distant enemies. Existing local retreat behavior still applies. Explicit attack orders can override the default movement policy. Escort host IDs are persisted and included in replay diagnostics.

## Deployment and loss handling

`get_deployed_fleet()` is the authoritative deployed subset. Battle setup, attempt ship IDs and initial replay/deployment snapshots use it, excluding reserves. Future RP/economy/aura consumers must use this subset rather than all owned ships. No new income source is implemented here.

Losing a deployment destroys only its actual participants. Surviving reserves remain owned and can be reactivated at a secured port; terminal defeat applies when no owned ships remain. Family-slot changes never create a free replacement. The new campaign's slot salvage path returns surviving material cells only, so destroyed equipment cannot be refunded by scuttling. Broader reconstruction/repair economics remain step 26.

## Persistence and migration

Checkpoints store the roster, stable families, role/reserve/escort fields and physical HP together. `family_identity_version=1` marks regular-slot names as display labels; family ID uniqueness is checked by the roster instead. Legacy metadata retains its original name validation.

Pre-policy active-campaign saves migrate by actual blueprint fingerprints, retaining physical IDs, damage, balances, ledger and frozen enemies. The first three physical families become active; additional families remain reserves. Pending deployment identities/snapshots are adjusted to that deployed subset. Migration is committed durably before loaded state is exposed. Historical legacy maps remain unchanged.

## Verification

`test_fleet_slots.gd` covers all mining restrictions, offensive capstones/craft, qualifying berths, mixed lab/cargo rejection, loose Offense limits, dead labs, one physical support per slot, alias/translation identity, direct/library fourth-family rejection, paid revisions, family swaps, reserve HP/reload, reserve exclusion from battle snapshots, reserve survival after deployment loss, invalid dedicated-role loads, durable pending-save migration, Escort movement and five-slot UI visibility. Future-equipment fixtures test policy only; they do not implement or sell those components.

The complete isolated baseline passed with zero assertion failures in `.local/checks/a2293bdd97704efdbd8b6d1a19d257ab/`, including 1,000 topology seeds, 1,000 content seeds, 1,080 encounter allocations, full campaign traversal, deterministic replay and 600 battle regressions. Subsequent UI refinements passed `.local/slots-focused-final.log`. Native 640×360 top/support-slot captures were inspected (`.local/fleet-slots-*.png`). `git diff --check` passed. Existing certificate-store and shutdown resource diagnostics remain separate from assertions.

## Deployment capacity (step 18 progress)

`FleetRules.ship_capacity` charges each living deployed hull `2 + ceil(occupied cells / 12) + active lab levels`. Occupancy uses unique surviving physical material cells, including loose material and all assembled cells (including engine exhaust). Bounding rectangles and connectivity do not affect cost. Partially damaged components retain their entire atomic footprint; destroyed units lose their cells and lab surcharge. Repair/reconstruction restores that cost. Only the highest living lab rank adds its surcharge (6/9/12-cell footprints for I/II/III); see SCIENCE.md.

`GameState.used_deployment_capacity()` sums only `get_deployed_fleet()`. Dedicated ships receive no exemption. Manual reserves, inactive families and dead hulls consume nothing. Act limits are 30/42/54, derived from campaign progression, including the existing secured-boss transition. Capacity is recomputed rather than saved as a potentially stale counter. No save migration or enemy-budget adjustment is needed. Historical legacy maps retain unrestricted deployment.

Players may own or build excess copies. `deployment_error()` blocks departure above capacity, including direct battle/noncombat travel entry points. It does not silently reserve or discard a ship. At secured ports, existing reserve/family controls let players choose their deployment. The Fleet summary shows current/maximum capacity, individual hull and construction tooltips show per-copy costs, and the departure control explains the rejection. Fleet changes refresh that control immediately.

`tests/test_fleet_capacity.gd` covers sparse hulls and rounding boundaries, loose/assembled cells, damage/reconstruction, lab ranks/destruction, all act limits, physical copy accounting, over-capacity ownership/departure rejection, reserve and family exclusion, reload, participant snapshots, live UI updates and legacy compatibility. The complete isolated baseline passed in `.local/checks/c8f8a4c00328453180f8437ba8e5adb0/` with zero failures, including 600 battle cases. Additional UI/family assertions passed in `.local/capacity-ui.log`. Native 640×360 capacity display inspected in `.local/fleet-slots-top.png`; diff whitespace checks passed. Existing certificate-store and shutdown diagnostics remain separate.

Step 18 is not complete. The 300-credit/four-ship starter switch remains pending functional Research Lab, Crew Quarters and Cargo Hold equipment (scheduled research/adjacency/cargo milestones). The current three-Drone start remains playable. Lab I and Crew Quarters are now functional; Cargo Holds remain unavailable until their effects work. Complete those dependencies before activating the Science Vessel/Civic Tender start and checking off the whole step.
