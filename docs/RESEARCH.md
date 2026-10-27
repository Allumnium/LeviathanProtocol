# Multi-grant research model

Step 21 turns the staged section 7 registry into a validated, shared grant model. The existing `data/definitions.json` already contains Foundation and 45 purchasable node definitions; their costs, IDs and design tuning are preserved. No future node is marked implemented, no purchase UI is enabled, and no equipment effect is claimed by defining its grant.

`ResearchRules.resolve(research_ids)` derives equipment IDs, highest unlocked ranks, ability IDs and concept modifiers from selected research IDs. `GameState.research_grants()` exposes that result, and `is_equipment_researched()` now reads its equipment grants. `is_equipment_available()` still separately requires an implemented live pattern. A Foundation grant for a Research Lab does not expose an unfinished lab recipe.

Applied Energy grants Laser and Double Laser together. Energy Manipulation grants a +10% beam/shield efficiency concept with the ordinary +30% cap, without granting a fictitious equipment component. Step 27 activates its firing/recharge effect and the shared purchase transaction; see SHARED_RESEARCH.md. Other concepts include Scan spectroscopy, Cargo Hold capacity 15 without refilling existing loads, and extractable material permissions.

Grant resolution is read-only and order independent. Repeated sources do not stack modifiers or duplicate equipment/abilities. Rank grants use the highest unlocked level. Set-valued extraction grants union their permissions, so Deep Extraction adds Tech/Civic without losing the Offense/Defense permissions from Basic Extraction. Numeric modifiers use the strongest value; boolean modifiers use OR. Returned nested data does not alias the registry. Unknown research IDs fail closed with empty grants and an error.

The resolver describes grants from supplied IDs; it does not authorize purchases, add missing prerequisites, spend RP, select branches or apply gameplay effects. The definition audit can deliberately resolve all node IDs to check coverage even though opposing paths cannot coexist in a real run. Existing run-state validation continues to reject illegal purchased selections. Acquisition transactions and construction enforcement remain scheduled work.

## Requirements and validation

`ResearchRules.requirements()` supplies separate fields for known/implemented/owned state, missing prerequisites, missing story gates, owned exclusions and a conflicting stored family commitment. Prerequisites use AND. This read-only model is ready for the grouped UI in step 22; a clear prerequisite list alone does not imply that an unimplemented node is purchasable.

Definition validation now checks:

- Unique grant/reference lists, positive finite research costs, an unrestricted zero-cost Foundation and nonempty effects.
- All prerequisite references and acyclic ancestry; mutually exclusive ancestors cannot create an impossible node.
- The four independent families and their two named paths, reciprocal opposite-path exclusions across all tiers, and no exclusions crossing families or locking shared/economic research.
- Known boss-story gates, existing physical rank recipes, unique rank grants and prerequisite access to the previous lab rank.
- Typed concept modifiers, material permissions, bounded efficiency targets/cap, and the no-refill capacity invariant.
- Ability grants having their source equipment through the same node or its ancestors.
- Exactly one research grant source for each of the 56 equipment definitions and each of the 20 abilities.

After four family commitments, 33 of the 45 purchasable node definitions remain accessible, including the selected paths. No branch choice locks another family. Schema and content revision numbers are unchanged because the content payload and saved research IDs did not change.

## Persistence and verification

Research IDs, branch choices, RP and story flags retain their existing save fields. Resolved grants are recomputed after load; no second mutable unlock ledger is introduced. New runs reset to Foundation. Existing blueprint identities, fleet HP, balances and transactions are unchanged.

`tests/test_research.gd` checks registry coverage, grouped equipment grants, concept-only grants, all rank levels, modifier union/idempotence/order independence, unknown-ID rejection, deep-copy isolation, AND prerequisites, boss gates, independent family commitments, the 33-node accessible count, save/reload/reset and the continued implementation gate. Corrupted-registry tests cover cycles, impossible prerequisites, missing grant sources, invalid ranks/gates/modifiers/costs and incomplete branch locks. The suite is included in `tests/run_baseline.ps1`; actual full-run results are recorded in TODO.md.

The full isolated baseline passed with zero failures in `.local/checks/f6d54539cfc946d3be21895be7eb23bf/`, including 1,000 topology seeds, 1,000 content seeds, 1,080 encounter allocations, three full campaign traversals, deterministic replay and 600 battle cases. Whitespace checks passed. Existing certificate-store and shutdown resource diagnostics remain separate from assertions.

Changed files: `scripts/research_rules.gd`, `game_definitions.gd`, `game_state.gd`, `tests/test_research.gd`, `tests/run_baseline.ps1`, and the checklist/documentation. No visual UI changed in this step.

## Grouped research UI (step 22)

New campaigns now use `research_panel.gd` through the existing Research tab. Historical legacy-map fixtures retain the old equipment-tree display. `ResearchViewModel` supplies grouped, depth-aware presentation over the shared registry and requirement model.

The left sidebar lists visible families and the RP balance. The center shows collapsible groups and path rows with tier columns, names, costs and explicit states (Owned, Ready, Need RP, Prerequisites, Story gate, Excluded). Groups with near-term options appear first and start expanded; near-term options stay emphasized even if their RP cost is not yet affordable. Three combat tiers fit at 640×360; longer shared paths can scroll horizontally, and the full list scrolls vertically. Family navigation opens and scrolls to a chosen group. The right sidebar provides selected-node state and a grant-review action.

Selecting a card opens a scrollable modal review. It explains one research source granting multiple items, shows material recipes and physical lab-rank footprints, describes concept effects, lists all prerequisites and story gates, and identifies opposing tiers plus later rewards on the same path. A permanent family commitment/no-respec warning stays pinned outside the scrolling text, beside the reviewed acquisition action. Missing prerequisites, owned conflicts and RP shortfalls are explicit. A refresh closes any stale review so it cannot retain an old availability state.

Implementation flags remain authoritative: planned research is hidden even with enough RP or completed prerequisites, and Foundation reviews omit unfinished equipment/abilities. The complete planned tree is exercised using detached fixture registries, not a player-facing preview switch or a change to production readiness flags. The live game currently shows owned Foundation knowledge and explains that additional options appear as their systems become ready.

The UI does not spend RP, mutate research IDs or implement gameplay effects. It exposes `purchase_requested` for the later authoritative transaction handler. An acquisition button appears only when a handler is connected and the selected implemented node is Ready, and only within the full review. No production handler is connected in this milestone. Future acquisition code must still revalidate the request and persist it atomically; presentation state is not authorization. Grouped research effects/purchases remain scheduled work, and step 18's starter switch is still pending its support-component dependencies.

Additional changed files: `scripts/research_view_model.gd`, `research_panel.gd`, `research_rules.gd` (catalog injection for the shared requirement model), `upgrades_panel.gd`, `game_map.gd`, `tests/test_research_ui.gd`, `tests/run_baseline.ps1`, and the checklist/documentation. This step adds no art assets or saved state fields.

The grouped UI suite covers production gating, all 46 fixture nodes, grouped recipes, concepts, lab ranks, AND prerequisites, story/branch restrictions, independent families, depth columns, near-term emphasis, collapse/navigation, sidebars, modal lifecycle, pinned warnings, explicit request signaling, insufficient RP, stale-review closure, signal-driven updates and no run-state mutation from review. Full isolated regression passed in `.local/checks/4fdff359c3da40f380aa1c38df4a8e27/` with zero failures, including 600 battle cases. Final layout/lifecycle assertions also passed in `.local/research-ui-final.log`.

Native 640×360 captures were inspected: `.local/research-live.png`, `.local/research-family.png`, `.local/research-grants.png`, `.local/research-review.png`. The final native log has no script errors; whitespace checks passed. Existing certificate-store and shutdown diagnostics remain separate from assertions.

## Construction-path authorization (step 23)

`ResearchRules.selection_error()` now supplies the shared saved-selection and runtime authorization boundary. It requires Foundation, unique known IDs, all prerequisites and story gates, valid stored family commitments, and no opposing-path combination. `RunProgressData.validate()` delegates its research selection checks to it. A contradictory or incomplete selection produces no effective grants, including when IDs were changed directly without a research signal.

`GameState.research_grants()` caches only by the actual research IDs, story flags and branch choices. This avoids repeatedly resolving the full registry for every candidate assembly origin. Changing any input invalidates the key; returned data is a deep copy, so callers cannot alter cached permissions. Definition readiness remains a separate condition: a selected grant does not expose an unfinished equipment pattern.

Current-run authorization now covers automatic/manual assembly, loose-match choices, direct morph calls and discovery-animation entry/completion. The Assembly menu lists only authorized implemented patterns. A research signal invalidates its choices/preview without evaluating the hull: assembled instances, loose material and owned physical ships retain their identity, position, HP and design. Explicit post-unlock assembly can consume eligible loose cells, never an existing assembled component.

Direct and saved-library construction, active-family assignment, revision registration, reserve activation, reconstruction repair and departure all enforce the same current-run equipment/rank authorization. Dedicated-slot restrictions remain additional rules. An illegal owned hull may still be put into reserve so the player can recover a legal deployment. Research never replaces, refits or heals physical ships for free. This step guards the existing revision and reconstruction paths; it does not add a new physical-refit system or change repair prices.

Blueprint loading remains a planning operation. Imported/archived locked designs can be inspected and edited, and the Save tooltip explains their construction requirement. Loading or discovering an item does not authorize physical construction. The standalone designer explicitly permits the nine implemented blueprint recipes through its scene setting; it does not alter the run's research, implementation flags or construction checks. Both campaign and legacy-map physical departure now recheck research.

Construction also validates stable equipment identity and researched rank before initializing a physical hull. `FleetShip.initialize()` returns failure safely for malformed/empty designs rather than proceeding with an empty blueprint; the purchase path rejects invalid footprint/orientation data before spending resources, advancing ship IDs or registering a family. Assignment validates blueprint structure before changing roster state.

`tests/test_research_enforcement.gd` covers all four family conflicts, rank/story gates, invalid selections, mutable-cache isolation, imported/direct purchase and assignment/revision rejection with unchanged checkpoint/accounting state, assembly/discovery enforcement, unlocks preserving editor and physical identities, explicit loose assembly after authorization, paid reconstruction, reserve quarantine/reactivation, checkpoint reload, legal/illegal departure, forged equipment IDs/ranks/orientations, safe empty initialization and standalone planning isolation. The existing recipe UI fixture now explicitly grants Applied Energy before testing its Laser assembly.

The complete isolated baseline passed with zero failures in `.local/checks/dfc92165842348a2a3bd554337594eda/`, including the new enforcement suite, deterministic replay, campaign traversals and 600 battle cases. After consolidating saved-selection validation, final enforcement and run-state checks also passed (`.local/research-enforcement-final.log`, `.local/enforcement-run-state-final.log`). Native 640×360 locked/unlocked menu captures were inspected (`.local/enforcement-menu-locked.png`, `.local/enforcement-menu-unlocked.png`); the native log has no script errors and whitespace checks passed. Existing certificate-store and shutdown diagnostics remain separate from assertions.

Additional changed files: `scripts/research_rules.gd`, `game_state.gd`, `run_progress_data.gd`, `fleet_ship.gd`, `build_tilemap_area.gd`, `fleet_panel.gd`, `scenes/ship_designer.tscn`, `tests/test_research_enforcement.gd`, `test_recipes.gd`, `run_baseline.ps1`, and the checklist/documentation. No future purchases or equipment effects were enabled. Labs and battle RP snapshots are step 24; the four-ship starter switch remains tracked under step 18.

Step 27 activates the useful shared purchases, physical lab-rank research, finite repair stations and guided weapons. Production grouped views now connect the reviewed action to the durable purchase backend. See SHARED_RESEARCH.md for behavior, testing and the Gate C starter dependency.
