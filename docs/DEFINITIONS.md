# Versioned content definitions

`data/definitions.json` is the proposed content registry from the October 26 design. `GameDefinitions` validates and reads it; accessors return deep copies so callers cannot mutate shared content. A bad registry fails closed. The schema version describes its structure; the content revision identifies a content snapshot; each entry also has its own revision. These versions are separate from blueprint/archive saves and the future run-save format.

Stable string IDs are used for content references. Equipment also has an explicit numeric `type_id` and matching `enum_key`: existing IDs 0–8 remain unchanged, and new IDs 9–55 are appended in design catalog order after excluding existing components. Material IDs remain Offense=0, Defense=1, Tech=2, Civic=3. Legacy enum names SPECIAL/CORE and saved field names remain valid. Technology CORE=0 displays as Foundation. Do not serialize documentation row numbers as equipment IDs.

## Contents

- 56 equipment definitions: material recipes, lab-rank recipes, role/capstone flags and ability references.
- Foundation plus 45 purchasable research definitions: costs, prerequisites, story gates, independent exclusive families, and separate arrays of equipment, rank, ability and modifier grants. Step 3 uses these grants for run authorization and construction checks; purchasing and gameplay effects remain later work. See RUN_STATE.md for the metadata boundary.
- Eight encounter templates: objective identifiers, threat multipliers, explicit slots for required entities, frozen rosters, finite waves, rewards and environments. Empty roster/reward slots must be populated during frozen encounter generation; these are not playable encounters.
- Eleven node types and two edge types: inhabited/combat defaults, goods-grade references, bounded hazardous duration and explicit no-surprise-battle/no-RP travel properties. Per-node identity, connections, frozen goods and completion belong to later run state and graph generation.
- 20 ability definitions: source, targeting rule, shared cooldown, simulation clock and initial cooldown fraction. Unspecified ranges/radii are null; they require tuning during implementation, not implicit zero or unlimited range.
- Five environment definitions with initial tuning and three goods grades with frozen origin values and sell-then-refill ordering.

The current live component catalog still supplies working stats, textures and recipe transforms. `ShipPartPattern` attaches definition identity/revision and filters out unimplemented equipment. A registry entry alone cannot add an assembly recipe, a blueprint-load path or a purchasable research option. Eleven equipment types are marked implemented, including Crew Quarters and three physical Research Lab ranks (see ADJACENCY.md and SCIENCE.md); research purchases, abilities, encounters, nodes, edges, environments and goods remain staged. Future implementation must mark content ready only after its effects and persistence work. Planned recipes/tuning do not change current combat stats, prices or starting ships. Step 3 separately activates Foundation-only run authorization.

`GameDefinitions.validate` checks the version envelope, domain field types, stable/numeric identity uniqueness, recipes and references. Step 20 adds canonical recipe/rank ambiguity checks through `MaterialRecipe`; see RECIPES.md. Step 21 adds research graph, family/exclusion, rank, typed concept and complete grant-source validation through `ResearchRules`; see RESEARCH.md. Research pacing and runtime effects remain later TODO gates. Generated graph topology has its own campaign checks.

## Verification

`tests/test_definitions.gd` checks legacy numeric identities, all definition IDs, planned-content gating, multi-grants, concept-only grants, branch/story metadata, goods order, independent snapshots and malformed data. Checked-in unversioned fixtures exercise all nine legacy component IDs and preserve their materials, offsets and thruster exhaust cells through load/save. Existing reflected-recipe and archive tests remain in the battle suite.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_baseline.ps1` for import, definition tests and battle regressions, all with isolated user data. No run-save format is introduced by this step.

Actual step 2 validation (October 26, 2026): import exit 0, definition suite exit 0 with zero failures, battle suite exit 0 with zero failures, including 600 balance encounters. Logs: `.local/checks/af52f3e4351f43e19dc0a15498de12c7/`. The existing certificate-store diagnostic remains. `git diff --check` passed. New scripts have Godot-generated UID sidecars; imports also changed generated .godot caches.
