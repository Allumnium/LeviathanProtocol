# Baseline — October 26, 2026

TODO step 1 audit. No gameplay behavior changed.

## Checks

Engine: Godot 4.7.2 stable, official ed1daf0bf. Project targets 4.7, GL Compatibility, 640 × 360 logical viewport.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_baseline.ps1` from the repository (the process-only policy flag is needed on this machine; it does not change system policy). Override `-Godot` for another engine location. The runner uses a fresh workspace-local APPDATA before autoload initialization, isolating all user:// files, including settings and archive reads. It runs:

```text
godot --headless --path . --import
godot --headless --path . --script res://tests/test_definitions.gd
godot --headless --path . --script res://tests/test_run_state.gd
godot --headless --path . --script res://tests/test_transactions.gd
godot --headless --path . --script res://tests/test_encounter_independence.gd
godot --headless --path . --script res://tests/test_battle.gd
```

Actual initial results: import exit 0; battle suite exit 0, **0 failures**. The 600-encounter check reported damage min 2.50, mean 7.97, max 17.18. Both commands emitted `Failed to read the root certificate store`; no script/import failures were reported. This is a baseline environment diagnostic, not a new gameplay regression.

Initial logs and isolated saves: `.local/baseline/`. Copies of existing archive_progress.json, settings.cfg and ship_designs.json are in `.local/baseline/fixtures/`. These private local artifacts are ignored by git. No tests used the player's real save directory.

Runner verification repeated import successfully, but the battle suite exited 1 with four failures in `_test_scene`: automatic combat/salvage completion, map advancement, victory credits and report lifetime. It also raised an invalid `closed` property access on Button at test line 1035 after the completion assertions failed. Logs: `.local/checks/e0c456965ad542adabf90c1e66f8ae66/`. No gameplay code changed between the passing and failing runs. Treat the controller test as an intermittent baseline issue; investigate its randomness/timing and report lookup before using it as a reliable gate. The runner correctly propagates failure. The real blueprint save hash still matches its backup.

### Controller baseline follow-up

Investigation found two independent problems:

- Finishing-shot slow motion retained a spent projectile until `_process` cleared it. Synchronous physics stepping can therefore remain at 0.1x speed without render frames. `auto_battle.gd` now clears a spent cinematic projectile before choosing physics speed. A regression injects a spent shot and checks that the next physics tick advances at normal speed.
- Random encounter generation also made the settlement/UI test depend on pursuit balance: focused diagnostics reproduced COMBAT after 120 simulation seconds with one alien still alive and no projectiles. The test now checks deployment generation separately, then uses three seeded, stationary, nearby low-HP targets with weapons on cooldown for the controller/UI scenario. The 600-encounter balance suite and dedicated pursuit tests retain their existing coverage.

The report lookup now identifies the report script instead of assuming the final child is a report. Missing reports produce a phase/elapsed/enemy/projectile diagnostic and a failed assertion rather than an invalid Button signal access. Focused controller check passed with zero failures. Godot also emitted ObjectDB/resource shutdown warnings; these are separate from controller assertions and are not claimed fixed.

Changed files: scripts/auto_battle.gd, tests/test_battle.gd, docs/BASELINE.md and TODO.md. No serialized IDs, saves or economy rules changed.

Final validation: `tests/run_baseline.ps1` completed with import exit 0 and battle suite exit 0, zero failures, including all 600 balance encounters and the controller regression. Logs: `.local/checks/a9bd96eebce241348f50181df4ad845c/`. The certificate-store diagnostic remains. `git diff --check` passed. Generated .godot caches changed during imports.

## Compatibility and integration findings

- Existing Type IDs 0–8 and Category IDs 0–3 must remain stable. CORE material (3) will display as Civic; SPECIAL (2) is Tech. TechCategory.CORE will display as Foundation.
- Builder cells are 26 × 26; battle rendering references Ship.BUILD_CELL_SIZE. Preserve recipe transforms, weapon heading and exhaust cells.
- At the initial baseline, enemy scaling occurred in GameState.set_destination and AlienShip.create_random_fleet. Step 5 removed both player-fleet factors and updated those test expectations. Three starter Drones remain until step 18.
- Archive and blueprint persistence exists; full versioned run persistence and transaction recovery still need implementation. Autoloads read saves before individual tests override paths, which is why process-level isolation matters.
- Existing tests cover construction, archive storage, fleet ownership, withdrawal, combat and UI flows. Keep those regressions while adding focused state-machine checks.
- Godot import updates tracked `.godot` editor caches. Treat those as generated audit side effects, not gameplay edits.

## Asset audit

See `ASSET_MANIFEST.csv` for current raster assets and `EQUIPMENT_ASSET_STATUS.csv` for all 56 planned equipment types. Manifest IDs are asset identifiers, not serialized equipment enums. Sources/licenses are unknown unless separately documented; do not infer ownership from presence in the repository.

Nine existing components have referenced art. Thruster sheets use a 3 × 3 atlas: frame 0 idle, frame 1 startup for 0.1 s, frames 2–8 loop at 12 fps. Static thruster exports are retained but the catalog uses animated sheets. Project filtering is nearest. Rotation/reflection is handled by recipe/renderer code; pivots and visual heading still require visual QA before art commissioning. Existing alien roles and station/star art are available. The remaining 47 equipment types need artwork; reuse procedural fog/targeting effects where appropriate.

Step 2 is documented in DEFINITIONS.md, step 3 in RUN_STATE.md, and steps 4–5 in ACCOUNTING.md. Next is frozen proximity encounter allocation in step 6.
