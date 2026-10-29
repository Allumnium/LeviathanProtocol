param(
    [string]$Godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $projectRoot ('.local/checks/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $runRoot 'appdata') | Out-Null
New-Item -ItemType File -Force (Join-Path $projectRoot '.local/.gdignore') | Out-Null
$previousAppData = $env:APPDATA
try {
    # Windows Godot resolves user:// through APPDATA. Isolate before autoloads run.
    $env:APPDATA = Join-Path $runRoot 'appdata'
    & $Godot --headless --path $projectRoot --import --log-file (Join-Path $runRoot 'import.log')
    if ($LASTEXITCODE -ne 0) { throw "Import failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_definitions.gd --log-file (Join-Path $runRoot 'definitions.log')
    if ($LASTEXITCODE -ne 0) { throw "Definition suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_research.gd --log-file (Join-Path $runRoot 'research.log')
    if ($LASTEXITCODE -ne 0) { throw "Research definition suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_research_ui.gd --log-file (Join-Path $runRoot 'research-ui.log')
    if ($LASTEXITCODE -ne 0) { throw "Grouped research UI suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_research_focus.gd --log-file (Join-Path $runRoot 'research-focus.log')
    if ($LASTEXITCODE -ne 0) { throw "Research focus/journey suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_run_state.gd --log-file (Join-Path $runRoot 'run-state.log')
    if ($LASTEXITCODE -ne 0) { throw "Run state suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_research_enforcement.gd --log-file (Join-Path $runRoot 'research-enforcement.log')
    if ($LASTEXITCODE -ne 0) { throw "Research enforcement suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_science.gd --log-file (Join-Path $runRoot 'science.log')
    if ($LASTEXITCODE -ne 0) { throw "Science suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_adjacency.gd --log-file (Join-Path $runRoot 'adjacency.log')
    if ($LASTEXITCODE -ne 0) { throw "Adjacency suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_tuning.gd --log-file (Join-Path $runRoot 'tuning.log')
    if ($LASTEXITCODE -ne 0) { throw "Baseline tuning suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_shared_research.gd --log-file (Join-Path $runRoot 'shared-research.log')
    if ($LASTEXITCODE -ne 0) { throw "Shared research suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_passengers.gd --log-file (Join-Path $runRoot 'passengers.log')
    if ($LASTEXITCODE -ne 0) { throw "Passenger state suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_passenger_art.gd --log-file (Join-Path $runRoot 'passenger-art.log')
    if ($LASTEXITCODE -ne 0) { throw "Passenger cabin art/footprint suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_cargo.gd --log-file (Join-Path $runRoot 'cargo.log')
    if ($LASTEXITCODE -ne 0) { throw "Cargo state suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_cargo_arrivals.gd --log-file (Join-Path $runRoot 'cargo-arrivals.log')
    if ($LASTEXITCODE -ne 0) { throw "Cargo arrival suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_construction_orders.gd --log-file (Join-Path $runRoot 'construction-orders.log')
    if ($LASTEXITCODE -ne 0) { throw "Construction order suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_general_fleet.gd --log-file (Join-Path $runRoot 'general-fleet.log')
    if ($LASTEXITCODE -ne 0) { throw "General fleet/migration suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_bitmap_font.gd --log-file (Join-Path $runRoot 'bitmap-font.log')
    if ($LASTEXITCODE -ne 0) { throw "Bitmap font/setup suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_boarding.gd --log-file (Join-Path $runRoot 'boarding.log')
    if ($LASTEXITCODE -ne 0) { throw "Passenger boarding suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_passenger_losses.gd --log-file (Join-Path $runRoot 'passenger-losses.log')
    if ($LASTEXITCODE -ne 0) { throw "Passenger loss/debt suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_transactions.gd --log-file (Join-Path $runRoot 'transactions.log')
    if ($LASTEXITCODE -ne 0) { throw "Transaction suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_encounter_independence.gd --log-file (Join-Path $runRoot 'encounter-independence.log')
    if ($LASTEXITCODE -ne 0) { throw "Encounter independence suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_frozen_encounters.gd --log-file (Join-Path $runRoot 'frozen-encounters.log')
    if ($LASTEXITCODE -ne 0) { throw "Frozen encounter suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_entity_objectives.gd --log-file (Join-Path $runRoot 'entity-objectives.log')
    if ($LASTEXITCODE -ne 0) { throw "Entity objective suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_retry_settlement.gd --log-file (Join-Path $runRoot 'retry-settlement.log')
    if ($LASTEXITCODE -ne 0) { throw "Retry settlement suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_battle_replay.gd --log-file (Join-Path $runRoot 'battle-replay.log')
    if ($LASTEXITCODE -ne 0) { throw "Battle replay suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_campaign_graph.gd --log-file (Join-Path $runRoot 'campaign-graph.log')
    if ($LASTEXITCODE -ne 0) { throw "Campaign graph suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_campaign_traversal.gd --log-file (Join-Path $runRoot 'campaign-traversal.log')
    if ($LASTEXITCODE -ne 0) { throw "Campaign traversal suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_fleet_slots.gd --log-file (Join-Path $runRoot 'fleet-slots.log')
    if ($LASTEXITCODE -ne 0) { throw "Fleet slot suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_review_fixes.gd --log-file (Join-Path $runRoot 'review-fixes.log')
    if ($LASTEXITCODE -ne 0) { throw "Review regression suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_ui_review.gd --log-file (Join-Path $runRoot 'ui-review.log')
    if ($LASTEXITCODE -ne 0) { throw "UI review suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_fleet_capacity.gd --log-file (Join-Path $runRoot 'fleet-capacity.log')
    if ($LASTEXITCODE -ne 0) { throw "Fleet capacity suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_ship_stats.gd --log-file (Join-Path $runRoot 'ship-stats.log')
    if ($LASTEXITCODE -ne 0) { throw "Shared ship stats suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_recipes.gd --log-file (Join-Path $runRoot 'recipes.log')
    if ($LASTEXITCODE -ne 0) { throw "Recipe suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_basic_ships.gd --log-file (Join-Path $runRoot 'basic-ships.log')
    if ($LASTEXITCODE -ne 0) { throw "Basic ship suite failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_battle.gd --log-file (Join-Path $runRoot 'tests.log')
    if ($LASTEXITCODE -ne 0) { throw "Battle suite failed: $LASTEXITCODE" }
} finally {
    $env:APPDATA = $previousAppData
    Write-Output "Isolated saves and logs: $runRoot"
}
