# Resolved development thoughts

Resolved entries moved from [THOUGHTS.md](THOUGHTS.md), preserving their context and outcomes. This is a reference, not an active backlog or authorization to change gameplay. Open follow-ups remain in THOUGHTS.md or [TODO.md](TODO.md).

## 2026-11-07 - Explicit research context and document facts (partial resolution)

- **Original refactor context (2026-11-07):** Pass the owning run context directly to extracted systems and remove the hangar projection adapter; avoid treating mutable GameState fields and the committed document as two permanent authorities. The Fleet/catalog portion was resolved separately below.
- **Resolved portion 2026-11-07:** Research choices, allocation/offer preparation, grants, family commitments, story gates and registry validation now propagate the owning frozen database. FactView derives matching capabilities, card count and M/XL lab output from run rows, including zero-hull survival, destroyed hosts and chassis/research multipliers. Runtime/UI production no longer builds combat/art objects. Direct tests deliberately bind different global rules and preserve custom gates/families, costs and grants; replay and failure checks cover completion hooks and overflow offers. Travel/settlement staging, checkpoint validation and final projection removal remain open in THOUGHTS.md/TODO.md.

## 2026-11-07 - Explicit Fleet/shipyard content context (partial resolution)

- **Original refactor opportunity (2026-11-07):** The temporary frozen Content binding protects existing consumers while P3c extracts the remaining systems. Pass the owning run context directly to those systems and remove the hangar projection adapter; avoid treating the mutable GameState fields and committed document as two permanent authorities.
- **Resolved portion 2026-11-07:** Fleet/shipyard commands now mutate private run transactions and receive the owning frozen database explicitly. Content projections, SlotCatalog, GameDefinitions, loadouts, research catalog lookup and squadron fitting propagate that context without rebinding global content. Ship allocation constructs data directly without loading combat objects or artwork. FactView shares hull/repair/station queries, and one GameState bridge publishes after commit. Focused tests use a deliberately different global database and verify prices/default fits remain owned by the transaction. Remaining systems, semantic validation and adapter removal stay open in THOUGHTS.md and TODO.md.

## 2026-11-07 - Starter package ownership

- **Original question (2026-11-07):** Keep engine-wide equipment and fleet packages in core, but put the current campaign's selected starter package and resources in leviathan. This lets another scenario reuse the mechanics without inheriting the convoy charter. P2 can introduce a small start definition now; P6 can compose it into scenario recipes.
- **Resolved 2026-11-07:** Added `core:convoy` as a reusable fitted fleet package and `leviathan:charter` as the campaign's starting resources and dock. No new player setup controls are needed for this phase; P6 can expose starts through scenario recipes.

## 2026-11-07 - Cached content views

- **Original refactor opportunity (2026-11-07):** GameDefinitions, SlotCatalog and ShipLoadouts keep independent static caches. When the editor reloads a pack, those caches can retain previous definitions. Tie cache lifetime to the loaded database or remove the duplicate caches as callers move to Content.
- **Resolved 2026-11-07:** GameDefinitions, SlotCatalog and ShipLoadouts now invalidate their caches when the loaded DefDatabase changes. A patch-only integration check warms the original views, replaces content, verifies patched reads and restores the original database. The remaining UI/static-cache audit stays open in THOUGHTS.md.
- **Further resolved 2026-11-07 (P2d):** Shared support parameter caching also follows DefDatabase replacement. The combat fixture warms shipped values, replaces content and verifies actual patched repair behavior and restored defaults.

## 2026-11-07 - Frozen fares

- **Resolved observation (2026-11-07):** Cargo and passenger loads keep their departure unit value. Validation must allow a valid stored fare that differs from today's economy definition; otherwise changing a fare could invalidate an occupied ship.
- **Resolution 2026-11-07:** P2 starter/economy validation accepts bounded positive stored fares and tests that they survive a change in current economy definitions. P3 content snapshots remain planned in TODO.md.

## 2026-11-07 - Active-suite stale fixtures

- **Original concern (2026-11-07):** Four focused suites have documented failures from before P1. Distinguish stale fixtures from gameplay defects before using them to assess refactors; otherwise a new regression could hide inside an accepted failure count.
- **Resolved active portion 2026-11-07:** The three recorded active-suite failures came from old formation coordinates, Map/Fleet expectations, former lab output and fixed-speed assumptions. The ammunition suite also still expected three alien missiles and admitted a post-incident event without its required story flags. Fixtures were corrected while preserving their transaction and gameplay assertions; flagship selection 307, research travel 260, expedition events 90 and fleet missiles 118 checks passed with zero failures. Legacy archive-suite retirement remains open in THOUGHTS.md and TODO.md.

## 2026-11-07 - Frozen setup fixture

- **Original observation (2026-11-07):** The ammunition UI fixture changed simulation supply after the deployment screen had rendered, then expected the combat-only refresh to run during frozen setup. Establish empty supply before admission so the fixture tests the actual saved-supply path; hidden setup speed controls should not count as visible overlap.
- **Resolved 2026-11-07:** The fixture now establishes empty saved supply before admission and checks visible controls for overlap. The focused fleet-missile suite passed 118 checks with zero failures without changing gameplay.

## 2026-11-07 - Research content authority and card metadata

- **Original observation (2026-11-07):** JSON is loaded through the new pack pipeline, but research grants are still filtered and rewritten in code. An inspector could show a valid edit that gameplay ignores. P2 should prove changes through real gameplay transactions, not only database lookups.
- **Original UX concern, research portion (2026-11-07):** Some authored ability and research definitions still describe retired or unavailable behavior. Do not expose those as usable options just because a generic Library form can display them. Make availability explicit while preserving current gameplay.
- **Resolved research portion 2026-11-07:** Canonical research definitions now contain the effective grants, offer status, descriptions and missing-equipment messages. Equipment definitions declare ordinary/research/unavailable access. Shared tuning supplies bar increments and card counts; families and story gates are definitions. ID-based filters, grant/prerequisite rewrites and active card-text overrides are removed. The captured 18 internal nodes, 16 visible descriptions and 40 equipment-access variants match the original effective behavior.
- **Verification:** A fixture changes real offers, grants, family/gate behavior, fitted laser damage and travel income, including a new inherited card, Continue and failed-save rollback: 48 checks. Native authored cards and an actual pointer choice pass 26 checks across three resolutions. Invalid patches, including malformed referenced definitions, transitive cycles and changes to family paths, disable the patching pack while core content remains intact. Remaining ability metadata stays open in THOUGHTS.md.

## 2026-11-07 - Ability metadata and registered modifier schemas

- **Original UX concern (2026-11-07):** Some ability definitions describe retired or unavailable behavior. Do not expose those as usable options just because a generic Library form can display them; research availability was resolved earlier, with ability authority left for P2d.
- **Resolved 2026-11-07:** Abilities explicitly declare research/unavailable status. Unimplemented descriptions say they are unavailable; the current player context rejects unavailable abilities and offered research cannot grant them. Ion Pulse retains its original shipped mechanics. Registered behavior/parameter schemas validate the existing engine operations; actual patched casts and unavailable-option rejection pass the combat fixture.
- **Original editor opportunity (2026-11-07):** Research modifier validation has one implementation, but the inspector registry needs parameter schemas so authors can select supported primitives rather than discover names through errors.
- **Resolved 2026-11-07:** Added shared research-modifier and ability-behavior schemas plus the support behavior schema. Runtime research validation now consumes the same registered modifier forms as pack loading and exported JSON schemas; the future inspector can inspect those forms without a separate parameter whitelist. Focused research content/redesign/pack checks pass.

## 2026-11-07 - Retired archive diagnostics

- **Original note (2026-11-07):** **Concern / remaining legacy diagnostics:** The five pre-existing square-checkpoint fixture failures remain with `test_legacy_archives`, pending its reference audit and retirement in P2e. The active-suite stale-fixture corrections are recorded in [the archive](THOUGHTS_ARCHIVE.md).
- **Resolved 2026-11-07 (P2e):** Audited references and deleted the archive-only square/hex readers, their isolated helpers/data, the three fixtures and retired suite. Active scripts/scenes/tests have no remaining references. Shared combat DTOs and current campaign/checkpoint dependencies remain; the five obsolete decoder failures no longer belong to the test set.

## 2026-11-07 - Runtime projection caches

- **Original note (2026-11-07):** **Refactor opportunity / remaining caches:** Audit remaining UI/static caches as their authorities move in later P2 checkpoints. GameDefinitions, SlotCatalog, ShipLoadouts and shared support parameters now follow database replacement; their resolutions are archived.
- **Resolved 2026-11-07 (P2e):** Content now caches writable runtime projections by DefDatabase identity, and the migrated catalog/asset views invalidate on database replacement. The two-pack fixture verifies replacement/restoration after scoped fittings and grants. Full run-frozen tuning/art remains P3 work, recorded separately below.

## 2026-11-07 - Consistent Map trip estimates

- **Original note (2026-11-07):** **UX concern / contradictory trip estimates:** `_render_map_details` still formats selected-trip estimates at 1x and 10x, while the actual Map has fixed 8x controls and the underway estimate uses 8x. A focused future UX change should use the current travel speed consistently.
- **Resolved 2026-11-07 (P2e):** Selected-trip ETA now uses ExpeditionState.MAP_SPEED (8x), matching underway travel and researched cruise rate. Reviewed native captures at 640x360, 1280x720 and 1920x1080; the updated focused travel UI section passes 33 checks.

## 2026-11-07 - Direct pack-folder roots

- **Original note (2026-11-07):** **Tooling concern / pack-root diagnostics:** PackLoader discovers packs inside root directories. Passing a pack directory itself can produce a warning about its `defs` child instead of loading that pack. The CLI comment calls roots "pack folders," which is easy to misread. Consider accepting both forms or reporting the expected container layout explicitly.
- **Resolved 2026-11-07 (P2e):** PackLoader accepts either a container or a folder containing pack.json. Overlapping direct/container/absolute paths are deduplicated by physical directory; distinct packs with duplicate manifest IDs still fail. Focused checks confirm identical shipped content hashes and no spurious Problems. The CLI comment describes both forms.

## 2026-11-07 - Fleet and start preflight

- **Original note (2026-11-07):** **Refactor opportunity / relational validation:** Schemas validate new start/package fields, and new-run preflight rejects duplicate member IDs, unavailable fits, multiple flagships and oversized fleets. Moving reusable cross-definition checks into the loader's type-check registry would let the future Problems panel diagnose these before Playtest.
- **Resolved 2026-11-07 (P2e):** Added loader checks for complete compatible/obtainable loadouts, matching chassis defaults, unique member IDs, the live fleet limit, exactly one flagship, ordinary starting equipment and accessible starting docks. Causal references blame and roll back the patching pack, including edits to referenced chassis/equipment/location definitions. The focused relations suite passes 31 checks.

## 2026-11-07 - Retired research readers and prices

- **Original note (2026-11-07):** **Refactor opportunity / retired research views:** Active cards now read shared `research_tuning` for costs and counts. The unused focused-research/tree readers and nominal `cost_rp` metadata still exist for the legacy audit. Remove them in P2e so Library forms do not imply that an ignored per-project price controls the shared bar.
- **Resolved 2026-11-07 (P2e):** Removed unused focus/tree/effect-summary readers and nominal cost_rp metadata from definitions, validation and both schema sets. Active cards use the shared research bar and authored descriptions. Removed three obsolete text assertions; 205 active combat-effect checks pass.

## 2026-11-07 - Scoped runtime identities

- **Original note (2026-11-07):** **Refactor concern / qualified identities:** Qualified family and gate references now work, with a single commitment identity for qualified/local family aliases and explicit gate-to-run-flag bindings. Other legacy registry views still require globally unique local research/equipment IDs. Finish their move to scoped Content lookups before claiming complete namespace support for independent packs.
- **Resolved 2026-11-07 (P2e):** Content.view resolves schema references in the owning pack without changing authored data. Shipped owner scopes retain fixed shorthand; external identities remain qualified even when globally unique. Two independent same-name packs pass actual starter/fitting/refit/research/encounter/rescue/Continue checks, plus native card/refit interactions. Explicit core references cannot be rebound to a namesake. Registry primitive metadata uniqueness is scoped, and current engine enum lookups stay bound to core.

## 2026-11-07 - Actionable generation failures

- **Original note (2026-11-07):** **Observation and imaginative editor proposal / generation receipt:** The current allocator returns an empty encounter when required units cannot fit the budget. A structurally valid price edit can therefore need a feasibility diagnostic. An encounter inspector could show its budget as a receipt: mandatory units, reserved reinforcements, hazard share, tier prices and remaining points. This would explain an unaffordable composition or why a price change alters the roster. Reuse generation records rather than inventing a parallel allocator; add actionable failure details with the future composer/Problems work.
- **Resolved diagnostic portion 2026-11-07 (P2e):** Encounter generation can return per-call diagnostics naming the required unit, available points, minimum cost and reserved units. Actual story choices surface these errors while preserving receipts, resources, the pending choice and save bytes. Verified with a structurally valid unaffordable price patch. The proposed graphical generation receipt remains open in THOUGHTS.md for the composer/editor.

## 2026-11-07 - StableRng helper dispatch

- **Observed and resolved 2026-11-07 (P2e):** StableRng helper calls to unqualified randf/randi_range resolved to Godot globals, so ranged floats, chance, weighted choice, pick and shuffle could consume global randomness. Explicit self calls now keep those draws inside the stable stream. Added five independent reference/global-RNG-isolation checks; all 32 RNG checks pass. Versioned generation streams also have fixed encounter/research reference outputs and order/isolation/Continue checks.

## 2026-11-07 - Publishing new runs

- **Original note (2026-11-07):** **Persistence concern / publishing two files:** New runs require a frozen content file and a state file. Publish verified content first and treat the first durable run generation as the visibility/commit point; an orphan content folder must not appear as a resumable run. A failed new run must preserve the previous live run and its files. Existing AtomicRunStore considers a verified `.next` committed, so interruption after staging is recovery, not a failed transaction to roll back.
- **Resolved 2026-11-07 (P3a/b):** RunRepository verifies and publishes immutable content before the first AtomicRunStore commit. The durable state generation is the visibility point; content-only folders are ignored. Creation failures restore the previous live run/content binding and leave its files unchanged; verified staged generations remain recoverable committed state. Ordinary commits also verify the immutable content file has not disappeared or changed.

## 2026-11-07 - Installed and frozen rules

- **Original note (2026-11-07):** **Refactor concern / installed versus active content:** Existing static catalogs all read Content. Pack reloads must update the installed catalog without rebinding an active run to new rules. Introduce an explicit active frozen database binding while these callers are extracted, preserve the installed database for New Run, and verify failed loads restore the previous binding. Later run systems should take their context explicitly rather than swap globals during play.
- **Resolved runtime portion 2026-11-07 (P3a/b):** Content now separates the installed database from an active frozen run binding. New Run freezes installed definitions; installed reloads do not change active mechanics; Continue rebuilds resolved definitions, schemas and formula evaluators without source packs. Failed starts/loads restore the previous binding, and switching runs invalidates the existing catalog caches. The remaining explicit-context extraction stays open in THOUGHTS.md.

## 2026-11-07 - Removed source pack images

- **Original note (2026-11-07):** **Observation / missing pack art:** The architecture deliberately freezes definitions without copying assets. Current chassis/equipment validation and SurfaceArt can reject missing images; removing a source pack could therefore block Continue despite valid frozen rules. Missing files must use the established pink marker while real gameplay/schema errors still fail validation.
- **Resolved 2026-11-07 (P3a/b):** Chassis/equipment validation accepts absent referenced images while keeping gameplay checks. SurfaceArt loads external images and uses the established pink marker when a diffuse image disappears; available diffuse art still works without removed auxiliary maps. Actual frozen Continue preserves ownership/stats with source pack files removed. Focused native Fleet rendering confirms the markers and living ships.

## 2026-11-07 - Run-frozen tuning authority

- **Original note (2026-11-07):** **Refactor opportunity / run-scoped tuning:** `SharedSupport.parameters` now serves the shared behavior schemas, including enemy roles and research weapon effects. Move this lookup into the run's frozen content view during P3 and keep finite repair operations separate. Enemy roster/geometry/allocation snapshots already resist later tuning edits; full support/ability/art freezing belongs with P3 run content, not a second save system here.
- **Resolved runtime portion 2026-11-07 (P3a/b):** Active static support/ability/catalog reads now use the frozen run database and existing database-scoped caches. Definitions, references and parameter values remain stable across installed updates/removal and run switches. Assets are deliberately referenced rather than copied, following the architecture; removed images use pink markers. Replacing the temporary static binding with explicit system contexts remains part of P3c.

## 2026-11-07 - Run boundary JSON normalization

- **Observed and resolved 2026-11-07 (P3a/b):** Dictionary dot assignments in generated encounter copies introduced StringName keys, which the strict new run JSON guard rejected at Meridian battle admission. The schema normalizer now converts StringName keys/text and declared whole numbers at transaction/load boundaries. A focused regression covers this; story outcomes/Continue pass again. Ship, equipment-rank and squadron IDs also normalize to integers, preserving readable flag labels after Continue.

## 2026-11-07 - Repeated run validation cost

- **Observed and resolved 2026-11-07 (P3a/b):** Wrapping the existing semantic validator in a run document caused AtomicRunStore to reconstruct the same fleet repeatedly while inspecting main/staged/backup generations. A 33-ship refit exceeded the existing 500 ms limit. RunSession now retains at most eight exact validated-payload hashes within its immutable content context, with full-precision float keys and a regression rejecting a distinct invalid hull value. The focused persistence suite passes; slowest measured refit is 382 ms. No safety threshold was raised.
