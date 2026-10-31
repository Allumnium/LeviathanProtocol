# Current baseline

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run_baseline.ps1`.
Add `-Native` for actual Godot rendering/interaction checks and captures.
The runner isolates APPDATA so it cannot change real player saves.

Current suites:

- `test_hangar.gd`: physical purchases, fitting, transfers, damage, repairs and settlement.
- `test_hangar_persistence.gd`: malformed saves, backup recovery, failed commits, command limits, trade/losses, flagship defeat and refit timing.
- `test_hangar_campaign.gd`: six natural opening battles and all-act traversal/settlement.
- `test_hangar_research.gd`: ranked lab production, frozen pending yields, display rates and safe deferral of inactive equipment.
- `test_hangar_carriers.gd`: finite physical carrier craft, interception, source loss, reload/transfer conservation and actual battle UI.
- `test_hangar_intermediates.gd`: ship-wide magazine/computer stacking, railguns, command marks, research/purchase gates and six natural Act II combat fixtures.
- `test_hangar_mounts.gd`: size-led compatibility on all chassis, previous-loadout preservation, engine/forward restrictions, Transport cross-category fitting, native menus at three resolutions and real stacking loadouts.
- `test_hangar_playthrough.gd`: nine full-route natural runs with combat, trade and science purchasing policies, across three seeds. No forced wins or free research/credits.
- `test_hangar_ui.gd`: main-menu Continue, owned-item dropdowns, windows, layouts and actual battle/report integration.
- `test_legacy_archives.gd`: shared wire validation; read-only square checkpoint and square/hex/prototype libraries, malformed data, backup/staged recovery and byte preservation.
- `test_ship_stats.gd` and `test_battle_replay.gd`: shared engine/DTO regressions.

Forty-six older test/capture scripts are preserved as text under `docs/history/pre_hangar_tests/`, outside Godot's runnable tests. They describe removed material inventory, blueprint construction, reserves/capacity or old Designer/game-map paths. The earlier runner is preserved as `docs/history/run_baseline_PRE_HANGAR.ps1.txt`. Their old results do not validate the physical game. See `docs/LEGACY_BOUNDARIES.md`; do not restore retired gameplay to satisfy an archived fixture.
