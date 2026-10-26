param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$toolsDirectory = Join-Path $projectRoot '.tools'
$engineDirectory = Join-Path $toolsDirectory 'godot'
$engineExecutable = Join-Path $engineDirectory 'Godot_v4.7.2-stable_win64_console.exe'
$expectedSha256 = '731980F9608D61333E5BAF54A2EF17210ACC7A538446C0CB9969F002ACA1E953'

if (Test-Path -LiteralPath $engineExecutable) {
    Set-Content -LiteralPath (Join-Path $engineDirectory '_sc_') -Value ''
    & $engineExecutable --version
    if ($LASTEXITCODE -ne 0) { throw 'The local Godot engine could not run.' }
    return
}

New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
Set-Content -LiteralPath (Join-Path $toolsDirectory '.gdignore') -Value ''
$archivePath = Join-Path $toolsDirectory 'godot-4.7.2.zip'
if (-not (Test-Path -LiteralPath $archivePath)) {
    Write-Host 'Downloading the official portable Godot 4.7.2 engine...'
    Invoke-WebRequest -Uri 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip' -OutFile $archivePath
}
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $expectedSha256) {
    throw 'Godot archive checksum mismatch. The archive has not been extracted. Remove only .tools/godot-4.7.2.zip and try again.'
}
Expand-Archive -LiteralPath $archivePath -DestinationPath $engineDirectory -Force
Set-Content -LiteralPath (Join-Path $engineDirectory '_sc_') -Value ''
& $engineExecutable --version
if ($LASTEXITCODE -ne 0) { throw 'Godot was extracted but could not run.' }
Write-Host 'Godot is ready. It is stored only in this project; no system settings were changed.'
