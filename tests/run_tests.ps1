param(
    [string]$Godot = "C:\Users\PC\Desktop\Godot\Godot_v4.6.1-stable_win64_console.exe"
)

$project = Split-Path -Parent $PSScriptRoot
$scripts = @(
    "solo_test.gd",
    "remote_visual_test.gd",
    "upright_test.gd",
    "camera_yaw_test.gd",
    "climb_validation.gd",
    "climb_game_smoke.gd"
)

Write-Output "IMPORT"
$importOutput = & $Godot --headless --path $project --editor --quit 2>&1
$importCode = $LASTEXITCODE
$importOutput | Where-Object { $_ -match "DONE|ERROR|SCRIPT ERROR" } | ForEach-Object { $_.ToString() }
Write-Output "IMPORT EXIT $importCode"

$failed = $importCode -ne 0

foreach ($script in $scripts) {
    Write-Output ""
    Write-Output "TEST $script"
    $scriptPath = Join-Path $PSScriptRoot $script
    $output = & $Godot --headless --path $project --script $scriptPath 2>&1
    $code = $LASTEXITCODE
    $output | Where-Object { $_ -match "failures=|SOLO game=|ERROR:|SCRIPT ERROR:" } | ForEach-Object { $_.ToString() }
    Write-Output "$script EXIT $code"
    if ($code -ne 0) {
        $failed = $true
    }
}

Write-Output ""
Write-Output "STATIC CHECK"
$files = Get-ChildItem -Path $project -Recurse -File -Include *.gd,*.tscn,*.tres,*.godot,*.py,*.ps1 |
    Where-Object { $_.FullName -notlike "*\addons\*" -and $_.FullName -notlike "*run_tests.ps1" -and $_.Length -gt 0 }
$badPattern = @(
    ("TO" + "DO"),
    ("FIX" + "ME"),
    ("place" + "holder"),
    ("st" + "ub"),
    "ball_mode",
    "is_ball",
    "BallVisual",
    "ball_mesh",
    "toggle_ball_mode",
    ("Input\.is_action_pressed\(""stre" + "tch""\)"),
    "CheckButton"
) -join "|"
$bad = Select-String -Path $files.FullName -Pattern $badPattern -CaseSensitive:$false |
    Where-Object { $_.Path -notlike "*\docs\DESIGN.md" -and $_.Line -notmatch "placeholder_text|func _make_field" }
$empty = Get-ChildItem -Path $project -Recurse -File -Include *.gd,*.tscn,*.tres,*.godot,*.py,*.ps1 |
    Where-Object { $_.Length -eq 0 }
Write-Output "FILE COUNT: $($files.Count)"
Write-Output "STATIC BAD: $($bad.Count)"
Write-Output "EMPTY FILES: $($empty.Count)"
if ($bad.Count -gt 0 -or $empty.Count -gt 0) {
    $failed = $true
}

Write-Output ""
Write-Output "RESULT $(if ($failed) { 'FAILED' } else { 'PASSED' })"
exit $(if ($failed) { 1 } else { 0 })
