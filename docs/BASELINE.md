# Baseline — October 26, 2026

TODO step 1 audit. No gameplay behavior changed.

## Checks

Engine: Godot 4.7.2 stable, official ed1daf0bf. Project targets 4.7, GL Compatibility, 640 × 360 logical viewport.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_baseline.ps1` from the repository (the process-only policy flag is needed on this machine; it does not change system policy). Override `-Godot` for another engine location. The runner uses a fresh workspace-local APPDATA before autoload initialization, isolating all user:// files, including settings and archive reads. It runs:

```text
godot --headless --path . --import
godot --headless --path . --script res://tests/test_battle.gd
```

Actual initial results: import exit 0; battle suite exit 0, **0 failures**. The 600-encounter check reported damage min 2.50, mean 7.97, max 17.18. Both commands emitted `Failed to read the root certificate store`; no script/import failures were reported. This is a baseline environment diagnostic, not a new gameplay regression.

Initial logs and isolated saves: `.local/baseline/`. Copies of existing archive_progress.json, settings.cfg and ship_designs.json are in `.local/baseline/fixtures/`. These private local artifacts are ignored by git. No tests used the player's real save directory.

Runner verification repeated import successfully, but the battle suite exited 1 with four failures in `_test_scene`: automatic combat/salvage completion, map advancement, victory credits and report lifetime. It also raised an invalid `closed` property access on Button at test line 1035 after the completion assertions failed. Logs: `.local/checks/e0c456965ad542adabf90c1e66f8ae66/`. No gameplay code changed between the passing and failing runs. Treat the controller test as an intermittent baseline issue; investigate its randomness/timing and report lookup before using it as a reliable gate. The runner correctly propagates failure. The real blueprint save hash still matches its backup.

## Compatibility and integration findings

- Existing Type IDs 0–8 and Category IDs 0–3 must remain stable. CORE material (3) will display as Civic; SPECIAL (2) is Tech. TechCategory.CORE will display as Foundation.
- Builder cells are 26 × 26; battle rendering references Ship.BUILD_CELL_SIZE. Preserve recipe transforms, weapon heading and exhaust cells.
- Enemy scaling currently occurs in GameState.set_destination and AlienShip.create_random_fleet. Tests explicitly expect fleet-scaled encounters and three starter Drones; replace those expectations when steps 5/6 and 18 land.
- Archive and blueprint persistence exists; full versioned run persistence and transaction recovery still need implementation. Autoloads read saves before individual tests override paths, which is why process-level isolation matters.
- Existing tests cover construction, archive storage, fleet ownership, withdrawal, combat and UI flows. Keep those regressions while adding focused state-machine checks.
- Godot import updates tracked `.godot` editor caches. Treat those as generated audit side effects, not gameplay edits.

## Asset audit

See `ASSET_MANIFEST.csv` for current raster assets and `EQUIPMENT_ASSET_STATUS.csv` for all 56 planned equipment types. Manifest IDs are asset identifiers, not serialized equipment enums. Sources/licenses are unknown unless separately documented; do not infer ownership from presence in the repository.

Nine existing components have referenced art. Thruster sheets use a 3 × 3 atlas: frame 0 idle, frame 1 startup for 0.1 s, frames 2–8 loop at 12 fps. Static thruster exports are retained but the catalog uses animated sheets. Project filtering is nearest. Rotation/reflection is handled by recipe/renderer code; pivots and visual heading still require visual QA before art commissioning. Existing alien roles and station/star art are available. The remaining 47 equipment types need artwork; reuse procedural fog/targeting effects where appropriate.

Next: step 2, versioned definitions without exposing future purchases; then run/archive separation and atomic accounting in steps 3–4. No completion claims for those steps.
