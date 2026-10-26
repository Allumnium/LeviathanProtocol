# Run state and Archive knowledge

Step 3 keeps current-run authorization in GameState, separate from the persistent blueprint library and Archive discoveries. Starting a run resets research to Foundation, RP to zero, branch choices and story flags to empty, regular family assignments to the starter Drone family, credits/materials/upgrades to their starting values, and physical ships to fresh starters. Existing blueprint and discovery files remain intact.

`current_research_ids`, `research_points`, `research_branch_choices`, `story_flags` and `run_seed` belong to the run. Existing `fleet_design_slots` are the active regular families; `current_run_design_names` tracks names created during this run. Archived design names and discovered component IDs never grant research. Current-run research grants and implementation availability are separate queries, so an authorized but unfinished component still cannot be constructed.

Construction from either the editor or the saved-design library checks current-run equipment authorization before spending resources. A rejected saved design does not occupy a family slot. Affordable-rebuild detection also excludes locked designs. Blueprint loading and editing remain available for archived knowledge; the comprehensive assembly/import/refit/deployment checks remain step 23. No research purchasing UI or free research-grant API is introduced here. Existing combat fixtures explicitly authorize their required technologies rather than discovering them through Archive.

## Metadata boundary

`run_progress_snapshot()` returns versioned, independent metadata containing the seed, difficulty, signed credits, RP, research IDs, branch choices, story flags and active family/name lists. `restore_run_progress()` validates the entire metadata before changing anything. Unknown/duplicate research, missing prerequisites/story gates, opposite paths, malformed values and duplicate active families are rejected. Credits preserve their sign. The seed is a decimal string so JSON cannot round a 64-bit seed; current map generation uses that seed.

These methods are the metadata portion of the checkpoint format. They do not independently write a save file or restore physical fleet damage, inventory, encounter state, map progress or transaction history. Step 4's full checkpoint loader restores those together; see ACCOUNTING.md. Step 6 stores every generated node roster/reward explicitly (ENCOUNTERS.md). Exact simulation persistence and the new campaign map remain separate numbered steps; a seed alone does not replace frozen content.

Research purchasing and multi-grant effects, dedicated support roles/capacity, changed starter ships, and complete loaded-refit enforcement remain in their scheduled milestones. The current three Drone starters use only Foundation equipment and remain deployable.

## Verification

`tests/test_run_state.gd` covers archived-laser rejection without spending or slot mutation, explicit run authorization, preserved Archive files/designs across reset, seed reproduction, signed debt and 64-bit seed JSON round-trips, restored research/families/story flags, future-content gating, and rejection without partial mutations. It runs with the other suites through `tests/run_baseline.ps1` using isolated user data.

Actual step 3 validation (October 26, 2026): import, definitions, run-state and battle suites all exited 0 with zero failures; the battle suite includes 600 balance encounters. Logs: `.local/checks/445cb0a7d30d4ebf9204ba60d17fd634/`. The baseline certificate-store diagnostic remains. `git diff --check` passed. No player save files were used by these checks.
