> Archived reference (2026-11-04), not current instructions or an active backlog. See [current gameplay](../../HANGAR.md).

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
- `test_hangar_mounts.gd`: size-led compatibility on all chassis, previous-loadout preservation, engine/forward restrictions, Transport cross-category fitting, drop targets at three resolutions and real stacking loadouts.
- `test_hangar_drag.gd`: real viewport mouse drags, multi-select stock filters and ascending credit ordering, fitting/replacement/unequipping, invalid drops, save rollback, ownership and live ship statistics; supplied cargo-art thumbnails, snap bounds, proportions and removal/reload. Fitting camera checks cover pointer-centered zoom, middle-mouse pan, fixed cards/stars, per-ship refresh/tab persistence, shop/stock input isolation, zoom limits and floating/snapped equipment scale during zoom.
- `test_hangar_playthrough.gd`: nine full-route natural runs with combat, trade and science purchasing policies, across three seeds. No forced wins or free research/credits.
- `test_hangar_ui.gd`: main-menu Continue, stock/drop targets, windows, layouts and actual battle/report integration.
- `test_ui_polish.gd`: native formation box/group dragging, camera/selection persistence, deselection/Repair All and failed-save rollback, salvage confirm/cancel, stationary clickable stars, turret-circle alignment and actual map-flight transition/duplicate departure guard.
- `test_surface_art.gd`: all supplied chassis/equipment/asteroid/alien map sets, shared texture caching, packed height/occlusion channels and original diffuse preservation; higher-tier Wing/Sporeback art, encounter snapshot preservation and lit report previews. Projectile lights cover visibility/offscreen filtering, interpolation, zoom, colors, independent limits and expiry. With `-Native`, checks actual rotation-dependent lighting, transient illumination for all six alien map sets, moving/localized bullet and cursor lights, cursor-light disabling, asteroid atlas regions and pixel-identical unmapped-art fallback.
- `test_legacy_archives.gd`: shared wire validation; read-only square checkpoint and square/hex/prototype libraries, malformed data, backup/staged recovery and byte preservation.
- `test_ship_stats.gd` and `test_battle_replay.gd`: shared engine/DTO regressions.

Forty-six older test/capture scripts are preserved as text under `docs/history/pre_hangar_tests/`, outside Godot's runnable tests. They describe removed material inventory, blueprint construction, reserves/capacity or old Designer/game-map paths. The earlier runner is preserved as `docs/history/run_baseline_PRE_HANGAR.ps1.txt`. Their old results do not validate the physical game. See `docs/LEGACY_BOUNDARIES.md`; do not restore retired gameplay to satisfy an archived fixture.
