param(
    [string]$Godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$Native
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $projectRoot ('.local/checks/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $runRoot | Out-Null
$previousAppData = $env:APPDATA
$suites = @('hangar', 'hangar_persistence', 'hangar_campaign', 'swarm_navigation', 'hangar_research', 'research_combat', 'research_travel', 'hangar_healing', 'hangar_intermediates', 'hangar_mounts', 'ship_refit', 'hangar_squadrons', 'hangar_playthrough', 'hangar_ui', 'ui_polish', 'surface_art', 'ship_stats', 'battle_replay', 'chassis_review', 'whole_ship', 'battle_outcomes', 'battle_ui', 'fleet_missiles', 'flagship_selection', 'node_environment', 'sprite_collision', 'expedition_state', 'expedition_navigation', 'expedition_world', 'expedition_services', 'expedition_arrival', 'expedition_events', 'expedition_rewards', 'expedition_demo', 'expedition_ui_clarity')
$suites += 'research_abilities'
$suites += @('stable_rng', 'expr', 'packs', 'content_transactions', 'research_content', 'combat_content', 'generation_identity', 'content_namespaces', 'content_relations')
try {
    $env:APPDATA = Join-Path $runRoot 'appdata'
    foreach ($suite in $suites) {
        $log = Join-Path $runRoot ($suite + '.log')
        & $Godot --headless --path $projectRoot --script ('res://tests/test_' + $suite + '.gd') --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "$suite failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw "$suite emitted script errors" }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-expedition-ui-clarity.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_expedition_ui_clarity.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native expedition UI clarity failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native expedition UI clarity emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-expedition-events.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_expedition_events.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native expedition events failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native expedition events emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-expedition-arrival.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_expedition_arrival.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native expedition arrival failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native expedition arrival emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-expedition-services.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_expedition_services.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native expedition services failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native expedition services emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-node-environment.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_node_environment.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native node environment failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native node environment emitted script errors' }
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
        $log = Join-Path $runRoot 'native-battle-ui.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_battle_ui.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native battle UI failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native battle UI emitted script errors' }
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
    if ($Native) {
        $log = Join-Path $runRoot 'native-fleet-missiles.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_fleet_missiles.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native fleet missiles failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native fleet missiles emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-hangar-squadrons.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_hangar_squadrons.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native hangar squadrons failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native hangar squadrons emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-research-combat.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_research_combat.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native research combat failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native research combat emitted script errors' }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-research-travel.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_research_travel.gd --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "Native research travel failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native research travel emitted script errors' }
    }
    Write-Output "All $($suites.Count) current baseline suites passed."
} finally {
    $env:APPDATA = $previousAppData
    Write-Output "Isolated saves and logs: $runRoot"
}
