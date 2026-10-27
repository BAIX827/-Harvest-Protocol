param([string]$ZipPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ($ZipPath -eq '') { $ZipPath = Join-Path $projectRoot 'builds\Fieldworks-0.1.0-playtest.1-windows-x86_64.zip' }
$ZipPath = (Resolve-Path -LiteralPath $ZipPath).Path
$qaRoot = Join-Path $projectRoot ('tmp\qa\windows-package-' + [guid]::NewGuid().ToString('N'))
# Exercise a path with spaces and non-ASCII text even on Windows PowerShell 5.1.
$extract = Join-Path $qaRoot (([string][char]0x4e2d) + [char]0x6587 + ' path')
New-Item -ItemType Directory -Path $extract -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    foreach ($entry in $archive.Entries) {
        $resolved = [IO.Path]::GetFullPath((Join-Path $extract $entry.FullName))
        if (-not $resolved.StartsWith($extract + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive entry escapes the extraction directory.' }
    }
} finally { $archive.Dispose() }
Expand-Archive -LiteralPath $ZipPath -DestinationPath $extract
$packages = @(Get-ChildItem -LiteralPath $extract -Directory)
if ($packages.Count -ne 1) { throw 'Expected exactly one package directory.' }
$package = $packages[0].FullName
$expectedFiles = @('Fieldworks.exe','Fieldworks.pck','PLAYTEST_ZH.md','README.md','GODOT_LICENSE.txt','GODOT_COPYRIGHT.txt','BUILD_INFO.json','SHA256SUMS.txt')
$actualFiles = @(Get-ChildItem -LiteralPath $package -Recurse -File | Select-Object -ExpandProperty Name)
if (@(Compare-Object $expectedFiles $actualFiles).Count -ne 0) { throw 'Unexpected or missing package files.' }
$covered = @()
foreach ($line in Get-Content -LiteralPath (Join-Path $package 'SHA256SUMS.txt') -Encoding UTF8) {
    if ($line -notmatch '^([0-9a-f]{64})  ([^/\\]+)$') { throw 'Invalid checksum manifest line.' }
    $expectedHash = $Matches[1]
    $covered += $Matches[2]
    $file = Join-Path $package $Matches[2]
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) { throw "File checksum mismatch: $file" }
}
if (@(Compare-Object @($expectedFiles | Where-Object { $_ -ne 'SHA256SUMS.txt' }) $covered).Count -ne 0) { throw 'Checksum manifest must cover every payload file exactly once.' }
$exe = Join-Path $package 'Fieldworks.exe'
function Invoke-PackagePhase {
    param([string]$Phase, [string]$Slot)
    $log = Join-Path $qaRoot ($Phase + '.log')
    # Quote each absolute path for Start-Process' command-line join on Windows.
    $arguments = '--resolution 1440x900 --log-file "{0}" -- --verify-release="{1}" --verify-phase={2}' -f $log, $Slot, $Phase
    if ($Phase -eq 'boot') { $arguments = '--resolution 1440x900 --log-file "{0}" -- --smoke-test' -f $log }
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory $package -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(60000)) {
        Stop-Process -Id $process.Id -Force
        throw "Package $Phase timed out; only this verification process was stopped."
    }
    $process.Refresh()
    $output = Get-Content -LiteralPath $log -Raw -Encoding UTF8
    $marker = 'FIELDWORKS_RELEASE_' + $Phase.ToUpperInvariant().Replace('-','_') + '_OK'
    if ($Phase -eq 'boot') { $marker = 'FIELDWORKS_BOOT_OK' }
    if ($process.ExitCode -ne 0 -or $output -match 'SCRIPT ERROR:|ERROR:|Parse Error:' -or -not $output.Contains($marker)) { throw "Package $Phase failed: $log" }
    if ($Phase -eq 'boot') { Write-Host 'PASS: native exported normal startup (no verification override, no player save writes)'; return }
    $result = Get-Content -LiteralPath (Join-Path $Slot "result-$Phase.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($result.failures -ne 0 -or $result.render -eq 'headless') { throw "Invalid native package result: $Phase" }
    Write-Host "PASS: exported $Phase ($($result.checks) checks, $($result.render))"
}
Invoke-PackagePhase -Phase 'boot' -Slot ''
$routeSlot = Join-Path $qaRoot 'route-slot'
Invoke-PackagePhase -Phase 'write' -Slot $routeSlot
Invoke-PackagePhase -Phase 'read' -Slot $routeSlot
$exitSlot = Join-Path $qaRoot 'exit-slot'
Invoke-PackagePhase -Phase 'quit-save' -Slot $exitSlot
Invoke-PackagePhase -Phase 'discard' -Slot $exitSlot
$summary = [ordered]@{ zip=$ZipPath; sha256=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant(); extracted_package=$package; route_slot=$routeSlot; exit_slot=$exitSlot; completed_utc=[DateTime]::UtcNow.ToString('o'); status='passed' }
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $qaRoot 'package-result.json') -Encoding UTF8
Set-Content -LiteralPath (Join-Path $projectRoot 'tmp\qa\latest-windows-package-check.txt') -Value $qaRoot -Encoding UTF8
Write-Host "WINDOWS_PACKAGE_CHECKS_OK $qaRoot"
