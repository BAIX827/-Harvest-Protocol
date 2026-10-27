param([ValidatePattern('^[0-9A-Za-z][0-9A-Za-z.-]*$')][string]$Version = '0.1.0-playtest.1', [switch]$SkipChecks)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $engine)) { & (Join-Path $PSScriptRoot 'setup-godot.ps1') }
$engineVersion = (& $engine --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -ne '4.7.2.stable.official.ed1daf0bf') { throw "Unexpected engine: $engineVersion" }
if (-not $SkipChecks) { & (Join-Path $PSScriptRoot 'check-project.ps1') }
& (Join-Path $PSScriptRoot 'setup-export-templates.ps1')
$buildRoot = Join-Path $projectRoot 'builds'
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
Set-Content -LiteralPath (Join-Path $buildRoot '.gdignore') -Value ''
$name = "Fieldworks-$Version-windows-x86_64"
$stageRoot = Join-Path $buildRoot ('stage-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $stageRoot $name
New-Item -ItemType Directory -Path $package -Force | Out-Null
$executable = Join-Path $package 'Fieldworks.exe'
$output = & $engine --headless --path $projectRoot --export-release 'Windows Desktop' $executable 2>&1
$code = $LASTEXITCODE
$output | Set-Content -LiteralPath (Join-Path $stageRoot 'export.log') -Encoding UTF8
if ($code -ne 0 -or ($output -join "`n") -match 'SCRIPT ERROR:|ERROR:|Parse Error:') { throw "Export failed: $stageRoot/export.log" }
foreach ($file in @('Fieldworks.exe', 'Fieldworks.pck')) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $file))) { throw "Missing exported file: $file" }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\WINDOWS_PLAYTEST.md') -Destination (Join-Path $package 'PLAYTEST_ZH.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination $package
foreach ($file in @('GODOT_LICENSE.txt', 'GODOT_COPYRIGHT.txt')) { Copy-Item -LiteralPath (Join-Path $projectRoot "docs\$file") -Destination $package }
# Keep the full README's local links usable without shipping development logs or the PDF.
$readme = Get-Content -LiteralPath (Join-Path $package 'README.md') -Raw -Encoding UTF8
$readme = [regex]::Replace($readme, '!\[[^\]]*\]\([^)]+\)', '')
$readme = [regex]::Replace($readme, '\[([^\]]+)\]\((?!https?://)([^)]+)\)', '$1')
Set-Content -LiteralPath (Join-Path $package 'README.md') -Value $readme -Encoding UTF8
$commit = (& git -C $projectRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
$dirty = -not [string]::IsNullOrWhiteSpace((& git -C $projectRoot status --porcelain | Out-String))
$info = [ordered]@{version=$Version; source_commit=$commit; source_dirty=$dirty; engine=$engineVersion; target='Windows x86_64'; renderer='gl_compatibility'; save_format=6; created_utc=[DateTime]::UtcNow.ToString('o'); checks_skipped=[bool]$SkipChecks; signed=$false}
$info | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'BUILD_INFO.json') -Encoding UTF8
$hashes = Get-ChildItem -LiteralPath $package -File | Sort-Object Name | ForEach-Object { '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name }
$hashes | Set-Content -LiteralPath (Join-Path $package 'SHA256SUMS.txt') -Encoding UTF8
$zip = Join-Path $buildRoot ($name + '.zip')
Compress-Archive -LiteralPath $package -DestinationPath $zip -CompressionLevel Optimal -Force
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($zip + '.sha256') -Value "$zipHash  $name.zip" -Encoding ASCII
Write-Host "WINDOWS_PACKAGE_OK $zip"
Write-Host "SHA256 $zipHash"
Write-Host "SOURCE $commit DIRTY=$dirty"
