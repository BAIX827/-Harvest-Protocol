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
Set-Content -LiteralPath (Join-Path $projectRoot 'tmp\.gdignore') -Value ''

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
Invoke-GodotCheck -CheckName 'world' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_world.gd') -SuccessMarker 'FIELDWORKS_WORLD_TESTS_OK'
Invoke-GodotCheck -CheckName 'tools' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_tools.gd') -SuccessMarker 'FIELDWORKS_TOOLS_TESTS_OK'
Invoke-GodotCheck -CheckName 'simulation' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_simulation.gd') -SuccessMarker 'FIELDWORKS_SIMULATION_TESTS_OK'
Invoke-GodotCheck -CheckName 'crops' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_crops.gd') -SuccessMarker 'FIELDWORKS_CROP_TESTS_OK'
Invoke-GodotCheck -CheckName 'economy' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_economy.gd') -SuccessMarker 'FIELDWORKS_ECONOMY_TESTS_OK'
Invoke-GodotCheck -CheckName 'save' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_save.gd') -SuccessMarker 'FIELDWORKS_SAVE_TESTS_OK'
Invoke-GodotCheck -CheckName 'irrigation' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_irrigation.gd') -SuccessMarker 'FIELDWORKS_IRRIGATION_TESTS_OK'
Invoke-GodotCheck -CheckName 'sensor' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_sensor.gd') -SuccessMarker 'FIELDWORKS_SENSOR_TESTS_OK'
Invoke-GodotCheck -CheckName 'automation' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_automation.gd') -SuccessMarker 'FIELDWORKS_AUTOMATION_TESTS_OK'
$saveProcessDirectory = Join-Path $qaDirectory ('save-process-' + [guid]::NewGuid().ToString('N'))
Invoke-GodotCheck -CheckName 'save-write-process' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_save_process.gd', '--', 'write', $saveProcessDirectory) -SuccessMarker 'FIELDWORKS_SAVE_PROCESS_WRITE_OK'
Invoke-GodotCheck -CheckName 'save-read-process' -EngineArguments @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_save_process.gd', '--', 'read', $saveProcessDirectory) -SuccessMarker 'FIELDWORKS_SAVE_PROCESS_READ_OK'
Write-Host 'PASS: import, startup, world, tools, environment, crops, economy, saves, irrigation, sensors, automation and separate-process continuation checks.'
