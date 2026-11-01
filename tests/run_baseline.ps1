param(
    [string]$Godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$Native
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $projectRoot ('.local/checks/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $runRoot | Out-Null
$previousAppData = $env:APPDATA
$suites = @('hangar', 'hangar_persistence', 'hangar_campaign', 'swarm_navigation', 'hangar_research', 'hangar_carriers', 'hangar_intermediates', 'hangar_mounts', 'hangar_drag', 'hangar_playthrough', 'hangar_ui', 'ui_polish', 'surface_art', 'legacy_archives', 'ship_stats', 'battle_replay', 'chassis_review', 'whole_ship', 'battle_outcomes', 'flagship_selection')
try {
    $env:APPDATA = Join-Path $runRoot 'appdata'
    foreach ($suite in $suites) {
        $log = Join-Path $runRoot ($suite + '.log')
        & $Godot --headless --path $projectRoot --script ('res://tests/test_' + $suite + '.gd') --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "$suite failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw "$suite emitted script errors" }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-flagship-selection.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_flagship_selection.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native flagship selection failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native flagship selection emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-battle-outcomes.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_battle_outcomes.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native battle outcomes failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native battle outcomes emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-chassis-review.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_chassis_review.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native chassis review failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native chassis review emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-surface-art.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_surface_art.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native surface art failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|Shader compilation failed' -Quiet) { throw 'Native surface art emitted errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-ui.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_hangar_ui.gd --log-file $log -- --capture
        if ($LASTEXITCODE -ne 0) { throw "Native UI failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native UI emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-polish.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_ui_polish.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native polish failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native polish emitted script errors' }
    }
    Write-Output "All $($suites.Count) current baseline suites passed."
} finally {
    $env:APPDATA = $previousAppData
    Write-Output "Isolated saves and logs: $runRoot"
}
