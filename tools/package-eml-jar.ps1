#Requires -Version 5.1
<#
.SYNOPSIS
Repackages an administrator's separately licensed LLNL EML VM-250 archive
(e.g., EML-VM250-v1.0.2.tar.gz) into a single eml-vm250-<version>.jar file
containing only config/* and jars/*.jar for upload in OSCAR SensorHub Admin.

.DESCRIPTION
Never commit or distribute the input archive or generated JAR in OSCAR repositories.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$OutputJarPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input path does not exist: $InputPath"
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("oscar-eml-pack-" + [Guid]::NewGuid().ToString('N'))
$unpackDir = Join-Path $workDir 'unpacked'
$stageDir = Join-Path $workDir 'stage'

New-Item -ItemType Directory -Path (Join-Path $stageDir 'config') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageDir 'jars') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageDir 'META-INF') -Force | Out-Null

try {
    $item = Get-Item -LiteralPath $resolvedInput
    if ($item.PSIsContainer) {
        $bundleSearchRoot = $resolvedInput
    } else {
        New-Item -ItemType Directory -Path $unpackDir -Force | Out-Null
        $lowerName = $item.Name.ToLowerInvariant()
        if ($lowerName.EndsWith('.tar.gz') -or $lowerName.EndsWith('.tgz') -or $lowerName.EndsWith('.tar')) {
            $tarCmd = Get-Command tar.exe -ErrorAction SilentlyContinue
            if (-not $tarCmd) {
                throw 'Windows tar.exe is required to extract .tar.gz/.tgz/.tar EML archives.'
            }
            & $tarCmd.Source -xf $resolvedInput -C $unpackDir
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe failed to extract $resolvedInput (exit code $LASTEXITCODE)."
            }
        } elseif ($lowerName.EndsWith('.zip') -or $lowerName.EndsWith('.jar')) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($resolvedInput, $unpackDir)
        } else {
            throw "Unsupported EML input archive format: $resolvedInput"
        }
        $bundleSearchRoot = $unpackDir
    }

    $analysisXml = Get-ChildItem -LiteralPath $bundleSearchRoot -Recurse -File -Filter 'vm250Analysis.xml' |
        Select-Object -First 1
    if (-not $analysisXml) {
        throw "Could not locate config/vm250Analysis.xml inside $resolvedInput"
    }

    $configSrc = $analysisXml.Directory.FullName
    $bundleRoot = Split-Path -Parent $configSrc
    $jarsSrc = Join-Path $bundleRoot 'jars'
    if (-not (Test-Path -LiteralPath $jarsSrc -PathType Container)) {
        throw "Could not locate jars/ directory next to config/ in $resolvedInput"
    }

    Copy-Item -Path (Join-Path $configSrc '*') -Destination (Join-Path $stageDir 'config') -Recurse -Force
    $runtimeJars = Get-ChildItem -LiteralPath $jarsSrc -File -Filter '*.jar' |
        Where-Object { $_.Name -notlike '*-sources.jar' -and $_.Name -notlike '*-javadoc.jar' }
    if (-not $runtimeJars -or $runtimeJars.Count -eq 0) {
        throw "No runtime JARs found in $jarsSrc"
    }
    foreach ($jar in $runtimeJars) {
        Copy-Item -LiteralPath $jar.FullName -Destination (Join-Path $stageDir 'jars') -Force
    }

    $versionHint = 'custom'
    if ($item.Name -match '[vV]?(\d+\.\d+(?:\.\d+)?)') {
        $versionHint = $Matches[1]
    }

    if ([string]::IsNullOrWhiteSpace($OutputJarPath)) {
        $OutputJarPath = Join-Path (Get-Location).Path "eml-vm250-$versionHint.jar"
    }
    $outParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputJarPath))
    if (-not (Test-Path -LiteralPath $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $fullOutputJar = [System.IO.Path]::GetFullPath($OutputJarPath)
    if (Test-Path -LiteralPath $fullOutputJar) {
        Remove-Item -LiteralPath $fullOutputJar -Force
    }

    $manifestLines = @(
        'Manifest-Version: 1.0',
        'Bundle-Name: EML-VM250 Runtime Plugin Bundle',
        "Bundle-Version: $versionHint",
        'Created-By: OSCAR package-eml-jar',
        ''
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        (Join-Path $stageDir 'META-INF\MANIFEST.MF'),
        ($manifestLines -join "`r`n"),
        $utf8NoBom
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stageDir,
        $fullOutputJar,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $hash = (Get-FileHash -LiteralPath $fullOutputJar -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item -LiteralPath $fullOutputJar).Length
    Write-Output ("Packaged EML plugin JAR: {0} ({1} bytes, {2} runtime JARs, sha256={3})" -f $fullOutputJar, $size, $runtimeJars.Count, $hash)
} finally {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
