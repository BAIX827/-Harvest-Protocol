param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$templateDirectory = Join-Path $projectRoot '.tools\export-templates\4.7.2.stable'
$archivePath = Join-Path $projectRoot '.tools\Godot_v4.7.2-stable_export_templates.tpz'
$expectedSha512 = 'CA4D71C4D7B81DFC15D1A98BAA07534AA95B03FDDA78A0075B06672E1648D2E5F40980C9ADC28D23E1B92E732EE7BF3461997AA804AF74EC2FCD7A93CCB84079'
if (-not (Test-Path -LiteralPath $archivePath)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $archivePath) -Force | Out-Null
    Invoke-WebRequest -Uri 'https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz' -OutFile $archivePath
}
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA512).Hash -ne $expectedSha512) {
    throw 'Official template archive SHA512 mismatch; no files were extracted.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $versionEntry = $archive.GetEntry('templates/version.txt')
    $reader = New-Object IO.StreamReader($versionEntry.Open())
    try { $version = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
    if ($version -ne '4.7.2.stable') { throw "Unexpected template version: $version" }
    New-Item -ItemType Directory -Path $templateDirectory -Force | Out-Null
    foreach ($name in @('windows_release_x86_64.exe', 'windows_debug_x86_64.exe')) {
        $entry = $archive.GetEntry('templates/' + $name)
        if ($null -eq $entry) { throw "Missing official Windows template: $name" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDirectory $name), $true)
    }
} finally { $archive.Dispose() }
Write-Host 'PASS: official Godot 4.7.2 Windows x86_64 templates verified and extracted locally.'
