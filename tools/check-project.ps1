param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engineExecutable = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $engineExecutable)) {
    throw 'Godot is not ready. Run tools/setup-godot.ps1 first.'
}
Set-Content -LiteralPath (Join-Path (Split-Path -Parent $engineExecutable) '_sc_') -Value ''
$qaDirectory = Join-Path $projectRoot 'tmp\qa'
New-Item -ItemType Directory -Path $qaDirectory -Force | Out-Null

function Invoke-GodotCheck {
    param([string]$CheckName, [string[]]$EngineArguments, [string]$SuccessMarker = '')
    $checkOutput = & $engineExecutable @EngineArguments 2>&1
    $checkCode = $LASTEXITCODE
    $checkOutput | ForEach-Object { Write-Host $_ }
    $checkOutput | Set-Content -LiteralPath (Join-Path $qaDirectory "$CheckName.log") -Encoding UTF8
    $combinedOutput = $checkOutput -join "`n"
    if ($checkCode -ne 0 -or $combinedOutput -match '(?m)(SCRIPT ERROR:|ERROR:|Parse Error:)') {
        throw "$CheckName failed. Review tmp/qa/$CheckName.log."
    }
    if ($SuccessMarker -ne '' -and -not $combinedOutput.Contains($SuccessMarker)) {
        throw "$CheckName did not reach the expected startup marker."
    }
}

Invoke-GodotCheck -CheckName 'import' -EngineArguments @('--headless', '--path', $projectRoot, '--editor', '--import')
Invoke-GodotCheck -CheckName 'boot' -EngineArguments @('--headless', '--path', $projectRoot, '--', '--smoke-test') -SuccessMarker 'FIELDWORKS_BOOT_OK'
Write-Host 'PASS: project import and headless startup.'
