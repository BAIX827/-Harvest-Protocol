param([switch]$Editor)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engineDirectory = Join-Path $projectRoot '.tools\godot'
$engineExecutable = Join-Path $engineDirectory 'Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path -LiteralPath $engineExecutable)) {
    & (Join-Path $PSScriptRoot 'setup-godot.ps1')
}
Set-Content -LiteralPath (Join-Path $engineDirectory '_sc_') -Value ''
if ($Editor) {
    & $engineExecutable --path $projectRoot --editor
} else {
    & $engineExecutable --path $projectRoot
}
if ($LASTEXITCODE -ne 0) { throw "Godot exited with code $LASTEXITCODE" }
