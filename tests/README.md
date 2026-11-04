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

- [test_ship_refit.gd](test_ship_refit.gd): complete fits, equipment access and atomic refits.
- [test_hangar_squadrons.gd](test_hangar_squadrons.gd): group actions, stances and formation.
- [test_research_combat.gd](test_research_combat.gd), [test_research_travel.gd](test_research_travel.gd): earned research behavior.
- [test_expedition_services.gd](test_expedition_services.gd), [test_expedition_ui_clarity.gd](test_expedition_ui_clarity.gd): services and current UI.
- [test_hangar_persistence.gd](test_hangar_persistence.gd): atomic state and recovery; select only coverage needed for the change.

Do not rerun unchanged passing checks or test against real saves. Ask before expanding into a broad run. When explicitly requested, [run_baseline.ps1](run_baseline.ps1) runs broad headless coverage; `-Native` adds native suites. Documentation-only work needs link/content checks, not Godot suites.

Retired scripts under [docs/history/](../docs/history/) describe historical behavior, not new implementation requirements. See [LEGACY_BOUNDARIES.md](../docs/LEGACY_BOUNDARIES.md) for read-only compatibility.
