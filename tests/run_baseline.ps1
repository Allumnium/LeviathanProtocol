param(
    [string]$Godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $projectRoot ('.local/checks/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $runRoot 'appdata') | Out-Null
$previousAppData = $env:APPDATA
try {
    # Windows Godot resolves user:// through APPDATA. Isolate before autoloads run.
    $env:APPDATA = Join-Path $runRoot 'appdata'
    & $Godot --headless --path $projectRoot --import --log-file (Join-Path $runRoot 'import.log')
    if ($LASTEXITCODE -ne 0) { throw "Import failed: $LASTEXITCODE" }
    & $Godot --headless --path $projectRoot --script res://tests/test_battle.gd --log-file (Join-Path $runRoot 'tests.log')
    if ($LASTEXITCODE -ne 0) { throw "Battle suite failed: $LASTEXITCODE" }
} finally {
    $env:APPDATA = $previousAppData
    Write-Output "Isolated saves and logs: $runRoot"
}
