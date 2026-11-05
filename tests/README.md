# Focused verification

Run only the smallest relevant cases/files. Use a focused native visual/interaction check when UI visibility/input matters; headless scene-tree text alone is insufficient. Full baselines, every campaign variant, broad native acceptance and long soaks require an explicit user request.

From the project root, choose the affected suite and isolate saves:

```powershell
$godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$previousAppData = $env:APPDATA
$checkRoot = Join-Path (Get-Location) ('.local\checks\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $checkRoot | Out-Null
try {
    $env:APPDATA = Join-Path $checkRoot 'appdata'
    & $godot --headless --path . --script res://tests/test_research_travel.gd --log-file (Join-Path $checkRoot 'focused.log')
} finally {
    $env:APPDATA = $previousAppData
}
```

Replace the example suite with the relevant test file. For a supported native check, replace `--headless` with `--rendering-method gl_compatibility`. Await completion and inspect the suite summary, exit code and log for assertion/script/parse errors. A timeout or process exit alone does not establish that checks ran.

Useful focused entry points:

- [test_equipment_balance.gd](test_equipment_balance.gd): additive uplink/relay effects, source/expiry/capacity boundaries and 36 bounded 12-second weapon samples through actual firing/charge/projectile/damage paths. Writes equipment-comparison.json to isolated user://; controlled target motion, no campaign sweep.
- [test_research_redesign.gd](test_research_redesign.gd): all 20 active cards, capability-based effects and matching, missile range/firing, railgun hull-only damage, stacking, lab output, rare access, finite carrier/repair reserves, refits and Continue (headless).
- [test_research_choices.gd](test_research_choices.gd): shared 20/+20 RP progression, seeded three/four-card offers, hidden dependencies/branches/story gates, excess RP, depleted pools, atomic failures and Continue (headless); production card layout/pointer selection, shared X/reopening, existing-modal priority, saved-card requirements/disabled choices/restored matching equipment and travel pausing at supported resolutions (native).
- [test_research_abilities.gd](test_research_abilities.gd): earned physical abilities plus native production battle frame at 640x360/1280x720/1920x1080; shared side/footer bounds, pause/resume, pointer targeting, pan/zoom, enemy visibility/reinforcements/losses and the footer without abilities.
- [test_ship_refit.gd](test_ship_refit.gd): complete fits, exact-size lab/plate access and atomic refits.
- [test_hangar_research.gd](test_hangar_research.gd): M/XL lab production, Research Methods bonuses, removed L-lab rejection, hull boundaries, frozen travel yields and Continue.
- [test_hangar_squadrons.gd](test_hangar_squadrons.gd): group actions, stances and formation.
- [test_research_combat.gd](test_research_combat.gd), [test_research_travel.gd](test_research_travel.gd): earned research behavior.
- [test_research_command.gd](test_research_command.gd): command research progression, capacity boundaries, expanded-fleet Continue and atomic failures (headless); choosing an offered logistics card and Fleet capacity at supported resolutions (native).
- [test_fleet_scale.gd](test_fleet_scale.gd): 30 fighters/20 transports plus flagship, Continue, spawn limits, squadron health/reports, orders, spatial-query equivalence, cache invalidation and bounded clock catch-up. Headless defaults to focused logic plus a short 50-vs-40 profile; trailing `-- --checks-only` or `-- --profile` selects one. Native measures actual wall-clock pacing at the 5x setting at 1280x720, then reviews supported-resolution UI. `-- --battle-only` skips unchanged management checks; add `--performance-only` to skip unchanged post-profile layout captures, or `--fixed-budget` for the earlier fixed 60Hz frame workload. JSON records the mode, combat/wall time, requested/pending/dropped time and frame percentiles under isolated `user://`; compare modes separately. Broad profiles/soaks still require an explicit request.
- [test_expedition_services.gd](test_expedition_services.gd), [test_expedition_ui_clarity.gd](test_expedition_ui_clarity.gd): services and current UI.
- [test_hangar_persistence.gd](test_hangar_persistence.gd): atomic state and recovery; select only coverage needed for the change.

Do not rerun unchanged passing checks or test against real saves. Ask before expanding into a broad run. When explicitly requested, [run_baseline.ps1](run_baseline.ps1) runs broad headless coverage; `-Native` adds native suites. Documentation-only work needs link/content checks, not Godot suites.

Keep generated logs/captures under `.local/checks/<task>/`; `.local`, `.godot`, `*.log` and editor `*~` backups are Git-ignored. Existing archived backups stay versioned. Godot's `.import` resource settings and script `.uid` sidecars remain versioned; only generated `.godot` caches are untracked.

Retired scripts under [docs/history/](../docs/history/) describe historical behavior, not new implementation requirements. See [LEGACY_BOUNDARIES.md](../docs/LEGACY_BOUNDARIES.md) for read-only compatibility.
