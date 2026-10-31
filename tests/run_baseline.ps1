param(
    [string]$Godot = 'C:\Users\chris\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$Native
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runRoot = Join-Path $projectRoot ('.local/checks/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $runRoot | Out-Null
$previousAppData = $env:APPDATA
$suites = @('hangar', 'hangar_persistence', 'hangar_campaign', 'hangar_research', 'hangar_carriers', 'hangar_intermediates', 'hangar_mounts', 'hangar_playthrough', 'hangar_ui', 'legacy_archives', 'ship_stats', 'battle_replay')
try {
    $env:APPDATA = Join-Path $runRoot 'appdata'
    foreach ($suite in $suites) {
        $log = Join-Path $runRoot ($suite + '.log')
        & $Godot --headless --path $projectRoot --script ('res://tests/test_' + $suite + '.gd') --log-file $log
        if ($LASTEXITCODE -ne 0) { throw "$suite failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw "$suite emitted script errors" }
    }
    if ($Native) {
        $log = Join-Path $runRoot 'native-ui.log'
        & $Godot --path $projectRoot --rendering-method gl_compatibility --script res://tests/test_hangar_ui.gd --log-file $log -- --capture
        if ($LASTEXITCODE -ne 0) { throw "Native UI failed: $LASTEXITCODE" }
        if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet) { throw 'Native UI emitted script errors' }
    }
    Write-Output "All $($suites.Count) current baseline suites passed."
} finally {
    $env:APPDATA = $previousAppData
    Write-Output "Isolated saves and logs: $runRoot"
}
