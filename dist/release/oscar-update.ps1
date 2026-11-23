#Requires -Version 5.1
<#
.SYNOPSIS
OSCAR Zero-Login GitHub & Offline Bundle System Update Manager (Windows 11 + WSL 2)
Discovers, SHA-256 verifies, extracts to a clean sibling release directory, and
upgrades OSCAR in place (with automatic fail-safe rollback on failure) without
requiring a GitHub account, Personal Access Token, or docker.sock inside containers.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = 'help',
    [string]$Version = '',
    [string]$FromZip = '',
    [string]$Sha256 = '',
    [switch]$Staged,
    [switch]$BackupFirst,
    [switch]$Json,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$ScriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$SelfScript = Join-Path $ScriptRoot 'oscar-update.ps1'
$AgentTaskName = 'OSCAR-UpdateAgent'
$DisabledMarker = Join-Path $env:ProgramData 'OSCAR\update-bridge.disabled'
$DefaultGitHubBase = 'https://github.com/ORNL/oscar'
$GitHubBase = if ($env:OSCAR_UPDATE_GITHUB_BASE_URL) { $env:OSCAR_UPDATE_GITHUB_BASE_URL.TrimEnd('/') } else { $DefaultGitHubBase }
$MinFreeDiskGib = 4.0
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    switch ($ExtraArgs[$i].ToLowerInvariant()) {
        '--version' { if ($i + 1 -lt $ExtraArgs.Count) { $Version = [string]$ExtraArgs[++$i] } }
        '-version' { if ($i + 1 -lt $ExtraArgs.Count) { $Version = [string]$ExtraArgs[++$i] } }
        '--from-zip' { if ($i + 1 -lt $ExtraArgs.Count) { $FromZip = [string]$ExtraArgs[++$i] } }
        '-fromzip' { if ($i + 1 -lt $ExtraArgs.Count) { $FromZip = [string]$ExtraArgs[++$i] } }
        '--sha256' { if ($i + 1 -lt $ExtraArgs.Count) { $Sha256 = [string]$ExtraArgs[++$i] } }
        '-sha256' { if ($i + 1 -lt $ExtraArgs.Count) { $Sha256 = [string]$ExtraArgs[++$i] } }
        '--staged' { $Staged = [switch]::Present }
        '-staged' { $Staged = [switch]::Present }
        '--backup-first' { $BackupFirst = [switch]::Present }
        '-backupfirst' { $BackupFirst = [switch]::Present }
        '--json' { $Json = [switch]::Present }
        '-json' { $Json = [switch]::Present }
    }
}

function Assert-Administrator {
    if ($env:OSCAR_UPDATE_ALLOW_NONADMIN -eq '1') { return }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this command from an Administrator PowerShell / Command Prompt.'
    }
}

function Assert-AllowedGitHubOrigin {
    if ($env:OSCAR_UPDATE_ALLOW_CUSTOM_BASE_URL -eq '1') { return }
    if ($GitHubBase -ne $DefaultGitHubBase) {
        throw "Refusing untrusted GitHub release origin: $GitHubBase (expected $DefaultGitHubBase)."
    }
}

function Get-EnvFileValue {
    param([string]$Key, [string]$DefaultValue = '', [string]$FilePath = (Join-Path $ScriptRoot '.env'))
    if (-not (Test-Path -LiteralPath $FilePath)) { return $DefaultValue }
    $lines = Get-Content -LiteralPath $FilePath -ErrorAction SilentlyContinue
    $val = $DefaultValue
    foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))=(.*)$") {
            $candidate = $Matches[1].Trim()
            if ($candidate.Length -gt 0) { $val = $candidate }
        }
    }
    return $val
}

function Get-OscarVersion {
    $v = Get-EnvFileValue -Key 'OSCAR_VERSION' -DefaultValue ''
    if (-not $v) {
        $v = Get-EnvFileValue -Key 'OSCAR_VERSION' -DefaultValue 'local' -FilePath (Join-Path $ScriptRoot '.env.example')
    }
    return $v
}

function Assert-SemVer311 {
    param([string]$Ver)
    if ($Ver -notmatch '^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$') {
        throw "Invalid release version format: $Ver"
    }
    $maj = [int]$Matches[1]
    $min = [int]$Matches[2]
    if ($maj -lt 3 -or ($maj -eq 3 -and $min -lt 11)) {
        throw "In-place system update requires OSCAR 3.11.0 or newer (received $Ver)."
    }
}

function Test-SemVerGreater {
    param([string]$A, [string]$B)
    $cleanA = ($A -split '-')[0]
    $cleanB = ($B -split '-')[0]
    $pa = $cleanA -split '\.'
    $pb = $cleanB -split '\.'
    for ($k = 0; $k -lt 3; $k++) {
        $va = if ($k -lt $pa.Count) { [int]$pa[$k] } else { 0 }
        $vb = if ($k -lt $pb.Count) { [int]$pb[$k] } else { 0 }
        if ($va -gt $vb) { return $true }
        if ($va -lt $vb) { return $false }
    }
    return $false
}

function Get-AvailableDiskGib {
    try {
        $rootDrive = [System.IO.Path]::GetPathRoot($ScriptRoot)
        $di = New-Object System.IO.DriveInfo($rootDrive)
        return [math]::Round(($di.AvailableFreeSpace / 1GB), 1)
    } catch {
        return 32.0
    }
}

function Invoke-UpdateControlSh {
    param([string]$ShCmd, [string]$StdinText = '')
    $envFile = Join-Path $ScriptRoot '.env'
    $composeFile = Join-Path $ScriptRoot 'compose.yaml'
    $oscarCid = ''
    if (Test-Path -LiteralPath $envFile) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $oscarCid = ([string](& docker compose --project-name oscar --project-directory $ScriptRoot --env-file $envFile --file $composeFile ps --quiet oscar 2>$null)).Trim()
        } catch {} finally { $ErrorActionPreference = $prev }
    }
    $tmpIn = $null
    try {
        if (-not [string]::IsNullOrEmpty($StdinText)) {
            $tmpIn = Join-Path $env:TEMP "oscar-updctrl-in-$([Guid]::NewGuid().ToString('N')).tmp"
            [System.IO.File]::WriteAllText($tmpIn, $StdinText, $Utf8NoBom)
        }
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            if (-not [string]::IsNullOrWhiteSpace($oscarCid)) {
                if ($tmpIn) {
                    return ([string](& cmd.exe /c "type `"$tmpIn`" | docker exec -i $oscarCid sh -eu -c `"$ShCmd`" 2>nul"))
                }
                return ([string](& docker exec $oscarCid sh -eu -c $ShCmd 2>$null))
            }
            $ver = Get-OscarVersion
            if ($tmpIn) {
                return ([string](& cmd.exe /c "type `"$tmpIn`" | docker run --rm --label com.docker.compose.project=oscar-update-bridge -i --network none --user 10001:10001 -v oscar_oscar_state:/var/lib/oscar --entrypoint sh oscar:$ver -eu -c `"$ShCmd`" 2>nul"))
            }
            return ([string](& docker run --rm --label com.docker.compose.project=oscar-update-bridge --network none --user 10001:10001 -v oscar_oscar_state:/var/lib/oscar --entrypoint sh "oscar:$ver" -eu -c $ShCmd 2>$null))
        } finally { $ErrorActionPreference = $prev }
    } finally {
        if ($tmpIn) { Remove-Item -LiteralPath $tmpIn -Force -ErrorAction SilentlyContinue }
    }
}

function Test-BridgeAgentActive {
    try {
        $t = Get-ScheduledTask -TaskName $AgentTaskName -ErrorAction SilentlyContinue
        return [bool]($null -ne $t -and $t.State -ne 'Disabled')
    } catch {
        return $false
    }
}

function Test-UsbBackupAttached {
    try {
        $usbCfgPath = if ($env:OSCAR_USB_BACKUP_CONFIG) {
            $env:OSCAR_USB_BACKUP_CONFIG
        } else {
            Join-Path $env:ProgramData 'OSCAR\usb-backup.json'
        }
        if (-not (Test-Path -LiteralPath $usbCfgPath)) { return $false }
        $cfg = Get-Content -LiteralPath $usbCfgPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $cfg) { return $false }
        $p = [string]$cfg.targetPath
        if ([string]::IsNullOrWhiteSpace($p) -or (-not (Test-Path -LiteralPath $p))) { return $false }
        if (Test-Path -LiteralPath (Join-Path $p '.oscar-ejected')) { return $false }
        return (Test-Path -LiteralPath (Join-Path $p 'OSCAR-Backup\.oscar-usb-backup-root'))
    } catch {
        return $false
    }
}

function Write-BridgeStatusJson {
    param(
        [string]$State = 'IDLE',
        [string]$Stage = 'IDLE',
        [int]$Pct = 0,
        [string]$TargetVer = '',
        [string]$ReqId = '',
        [string]$JobAction = '',
        [string]$Message = '',
        [string]$LogTail = ''
    )
    $guiPref = (Get-EnvFileValue -Key 'OSCAR_GUI_UPDATE' -DefaultValue 'enabled').ToLowerInvariant()
    $guiEnabled = (-not (Test-Path -LiteralPath $DisabledMarker)) -and ($guiPref -ne 'disabled') -and ($guiPref -ne 'false')
    $bmode = Get-EnvFileValue -Key 'OSCAR_BACKUP_MODE' -DefaultValue 'disabled'
    $usbAttached = Test-UsbBackupAttached
    $nowIso = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

    $payload = [ordered]@{
        agentActive = (Test-BridgeAgentActive)
        guiUpdateEnabled = $guiEnabled
        backupPossible = ($usbAttached -or ($bmode -eq 'single'))
        state = $State
        stage = $Stage
        progressPercent = $Pct
        currentVersion = (Get-OscarVersion)
        releaseDir = $ScriptRoot
        availableDiskGib = (Get-AvailableDiskGib)
        updatedAt = $nowIso
    }
    if ($TargetVer) { $payload['targetVersion'] = $TargetVer }
    if ($Message) { $payload['message'] = $Message }
    if ($LogTail) { $payload['logTail'] = $LogTail }
    if ($ReqId) {
        $payload['activeJob'] = [ordered]@{
            requestId = $ReqId
            action = $JobAction
            state = $State
            stage = $Stage
            progressPercent = $Pct
            targetVersion = $TargetVer
            message = $Message
            updatedAt = $nowIso
        }
    }
    $jsonText = $payload | ConvertTo-Json -Depth 5 -Compress
    [void](Invoke-UpdateControlSh 'mkdir -p /var/lib/oscar/.moduledata/update-control/staged && cat > /var/lib/oscar/.moduledata/update-control/status.json.tmp && mv -f /var/lib/oscar/.moduledata/update-control/status.json.tmp /var/lib/oscar/.moduledata/update-control/status.json' $jsonText)
}

function Get-LatestGitHubRelease {
    Assert-AllowedGitHubOrigin
    $discoveredVer = ''

    try {
        $req = [System.Net.HttpWebRequest]::Create("$GitHubBase/releases/latest")
        $req.Method = 'GET'
        $req.AllowAutoRedirect = $false
        $req.UserAgent = 'OSCAR-SystemUpdater/3.11'
        $req.Timeout = 10000
        try {
            $resp = [System.Net.HttpWebResponse]$req.GetResponse()
        } catch [System.Net.WebException] {
            $resp = [System.Net.HttpWebResponse]$_.Exception.Response
        }
        if ($null -ne $resp) {
            $loc = [string]$resp.Headers['Location']
            $resp.Close()
            if ($loc -match '/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)(?:[/?#]|$)') {
                $discoveredVer = $Matches[1]
            }
        }
    } catch {}

    if (-not $discoveredVer) {
        $atomResp = Invoke-WebRequest -UseBasicParsing -Uri "$GitHubBase/releases.atom" -Headers @{ 'User-Agent' = 'OSCAR-SystemUpdater/3.11' } -TimeoutSec 15
        if ($atomResp.Content -match '/releases/tag/v([0-9]+\.[0-9]+\.[0-9]+)["/?<]') {
            $discoveredVer = $Matches[1]
        }
    }

    if (-not $discoveredVer) {
        throw "Unable to reach GitHub Releases at $GitHubBase (host may be offline; use -FromZip or GUI Offline Bundle Upload)."
    }
    Assert-SemVer311 $discoveredVer

    $dlUrl = "$GitHubBase/releases/download/v$discoveredVer/oscar-$discoveredVer.zip"
    $expectedSha = ''
    try {
        $shaResp = Invoke-WebRequest -UseBasicParsing -Uri "$dlUrl.sha256" -Headers @{ 'User-Agent' = 'OSCAR-SystemUpdater/3.11' } -TimeoutSec 15
        $shaText = if ($shaResp.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($shaResp.Content) } else { [string]$shaResp.Content }
        if ($shaText -match '\b([0-9a-fA-F]{64})\b') {
            $expectedSha = $Matches[1].ToLowerInvariant()
        }
    } catch {}

    return @{
        Version = $discoveredVer
        DownloadUrl = $dlUrl
        ExpectedSha256 = $expectedSha
    }
}

function Resolve-SiblingTargetDir {
    param([string]$TargetVer)
    $parentDir = Split-Path -Parent $ScriptRoot
    $parentLeaf = Split-Path -Leaf $parentDir
    if ($parentLeaf -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
        $grandDir = Split-Path -Parent $parentDir
        $verParent = Join-Path $grandDir $TargetVer
        New-Item -ItemType Directory -Path $verParent -Force | Out-Null
        $candidate = Join-Path $verParent "oscar-$TargetVer"
    } else {
        $candidate = Join-Path $parentDir "oscar-$TargetVer"
    }
    if ($candidate -ieq $ScriptRoot) {
        $stamp = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
        $candidate = "$candidate-r$stamp"
    }
    return $candidate
}

function Copy-DeploymentStateToTarget {
    param([string]$SrcDir, [string]$DstDir)
    $srcEnv = Join-Path $SrcDir '.env'
    if (-not (Test-Path -LiteralPath $srcEnv)) {
        throw "Active release directory $SrcDir is missing .env (run init before upgrading)."
    }
    Copy-Item -LiteralPath $srcEnv -Destination (Join-Path $DstDir '.env') -Force
    foreach ($sub in @('secrets', 'tls')) {
        $s = Join-Path $SrcDir $sub
        $d = Join-Path $DstDir $sub
        if (Test-Path -LiteralPath $s) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Copy-Item -Path (Join-Path $s '*') -Destination $d -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($receipt in @('.oscar-init-state', '.oscar-volume-adoption')) {
        $rPath = Join-Path $SrcDir $receipt
        if (Test-Path -LiteralPath $rPath) {
            Copy-Item -LiteralPath $rPath -Destination (Join-Path $DstDir $receipt) -Force
        }
    }
}

function Test-LocalHttpsReady {
    param([string]$TargetDir)
    $port = Get-EnvFileValue -Key 'OSCAR_HTTPS_PORT' -DefaultValue '443' -FilePath (Join-Path $TargetDir '.env')
    $curlExe = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (-not (Test-Path -LiteralPath $curlExe)) { return $true }
    for ($i = 0; $i -lt 30; $i++) {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            & $curlExe -fsSk --connect-timeout 3 --max-time 5 "https://127.0.0.1:$port/healthz" >$null 2>$null
            if ($LASTEXITCODE -eq 0) { return $true }
        } finally { $ErrorActionPreference = $prev }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Invoke-SystemUpgrade {
    param(
        [string]$TargetVer = '',
        [string]$ZipSource = '',
        [string]$ExpectedSha = '',
        [bool]$CreateBackupFirst = $false,
        [string]$ReqId = 'cli',
        [string]$JobAction = 'upgrade'
    )
    Assert-Administrator
    if (-not (Test-Path -LiteralPath (Join-Path $ScriptRoot '.env'))) {
        throw 'Current OSCAR directory is not initialized (.env not found).'
    }
    if ((Get-AvailableDiskGib) -lt $MinFreeDiskGib) {
        throw "Insufficient free disk space ($(Get-AvailableDiskGib) GiB available; >= $MinFreeDiskGib GiB required)."
    }

    $workTmp = Join-Path $env:TEMP "oscar-update-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $workTmp -Force | Out-Null
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    try {
        if (-not $ZipSource) {
            Write-BridgeStatusJson -State 'RUNNING' -Stage 'CHECKING' -Pct 10 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message 'Checking GitHub Releases (no login required)...'
            Assert-AllowedGitHubOrigin
            if (-not $TargetVer) {
                $rel = Get-LatestGitHubRelease
                $TargetVer = $rel.Version
                if (-not $ExpectedSha) { $ExpectedSha = $rel.ExpectedSha256 }
            } else {
                Assert-SemVer311 $TargetVer
                if (-not $ExpectedSha) {
                    $shaUrl = "$GitHubBase/releases/download/v$TargetVer/oscar-$TargetVer.zip.sha256"
                    $shaResp = Invoke-WebRequest -UseBasicParsing -Uri $shaUrl -Headers @{ 'User-Agent' = 'OSCAR-SystemUpdater/3.11' } -TimeoutSec 15
                    $shaTxt = if ($shaResp.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($shaResp.Content) } else { [string]$shaResp.Content }
                    if ($shaTxt -match '\b([0-9a-fA-F]{64})\b') { $ExpectedSha = $Matches[1].ToLowerInvariant() }
                }
            }
            if (-not $ExpectedSha) {
                throw "Could not retrieve SHA-256 checksum for oscar-$TargetVer.zip."
            }
        } else {
            if (-not (Test-Path -LiteralPath $ZipSource)) { throw "Bundle zip file not found: $ZipSource" }
            if (-not $TargetVer) {
                if ([System.IO.Path]::GetFileName($ZipSource) -match '^oscar-(\d+\.\d+\.\d+)') {
                    $TargetVer = $Matches[1]
                }
            }
            Assert-SemVer311 $TargetVer
        }

        if ($CreateBackupFirst) {
            $usbBackupScript = Join-Path $ScriptRoot 'oscar-usb-backup.ps1'
            $bmode = Get-EnvFileValue -Key 'OSCAR_BACKUP_MODE' -DefaultValue 'disabled'
            if ((Test-UsbBackupAttached) -and (Test-Path -LiteralPath $usbBackupScript)) {
                Write-BridgeStatusJson -State 'RUNNING' -Stage 'BACKING_UP' -Pct 22 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message 'Running zero-downtime incremental pre-upgrade sync to attached USB NVMe backup drive...'
                & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $usbBackupScript sync
                if ($LASTEXITCODE -ne 0) { throw 'Pre-upgrade USB NVMe backup sync failed; deployment was left untouched.' }
            } elseif ($bmode -eq 'single') {
                Write-BridgeStatusJson -State 'RUNNING' -Stage 'BACKING_UP' -Pct 22 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message 'Creating pre-upgrade encrypted backup snapshot...'
                & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $ScriptRoot 'oscar-setup.ps1') backup
                if ($LASTEXITCODE -ne 0) { throw 'Pre-upgrade backup failed; deployment was left untouched.' }
            }
        }

        if (-not $ZipSource) {
            $dlUrl = "$GitHubBase/releases/download/v$TargetVer/oscar-$TargetVer.zip"
            $dlDest = Join-Path $workTmp "oscar-$TargetVer.zip"
            Write-BridgeStatusJson -State 'RUNNING' -Stage 'DOWNLOADING' -Pct 38 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message "Downloading oscar-$TargetVer.zip from GitHub Releases..."
            $curlExe = Join-Path $env:SystemRoot 'System32\curl.exe'
            if (Test-Path -LiteralPath $curlExe) {
                & $curlExe -fL --retry 2 --connect-timeout 15 -A 'OSCAR-SystemUpdater/3.11' -o $dlDest $dlUrl
                if ($LASTEXITCODE -ne 0) { throw "Download failed for $dlUrl" }
            } else {
                Invoke-WebRequest -UseBasicParsing -Uri $dlUrl -OutFile $dlDest -Headers @{ 'User-Agent' = 'OSCAR-SystemUpdater/3.11' }
            }
            $ZipSource = $dlDest
        }

        Write-BridgeStatusJson -State 'RUNNING' -Stage 'VERIFYING_SHA256' -Pct 52 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message "Verifying SHA-256 cryptographic digest of oscar-$TargetVer.zip..."
        $actualSha = (Get-FileHash -LiteralPath $ZipSource -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ExpectedSha -and ($ExpectedSha.ToLowerInvariant() -ne $actualSha)) {
            throw "SHA-256 mismatch on $ZipSource (expected $ExpectedSha, computed $actualSha)."
        }

        Write-BridgeStatusJson -State 'RUNNING' -Stage 'EXTRACTING' -Pct 64 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message 'Extracting verified release into clean sibling directory...'
        $expandDir = Join-Path $workTmp 'expanded'
        Expand-Archive -LiteralPath $ZipSource -DestinationPath $expandDir -Force
        $topDirs = @(Get-ChildItem -LiteralPath $expandDir -Directory)
        if ($topDirs.Count -ne 1) {
            throw 'OSCAR release archive did not expand to a single top-level directory.'
        }
        $extractedRoot = $topDirs[0].FullName
        if (-not (Test-Path -LiteralPath (Join-Path $extractedRoot 'oscar-setup.ps1'))) {
            throw 'Extracted archive is missing oscar-setup.ps1.'
        }

        $targetDir = Resolve-SiblingTargetDir -TargetVer $TargetVer
        $prevBackup = ''
        if (Test-Path -LiteralPath $targetDir) {
            $prevBackup = "$targetDir.prev-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
            Move-Item -LiteralPath $targetDir -Destination $prevBackup -Force
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetDir) -Force | Out-Null
        Move-Item -LiteralPath $extractedRoot -Destination $targetDir -Force

        Copy-DeploymentStateToTarget -SrcDir $ScriptRoot -DstDir $targetDir

        Write-BridgeStatusJson -State 'RUNNING' -Stage 'UPGRADING_CONTAINERS' -Pct 78 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message "Building/loading OSCAR $TargetVer images and upgrading containers (persistent volumes retained)..."

        $upgradeOk = $false
        $prevPref = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $targetDir 'oscar-setup.ps1') upgrade
            if ($LASTEXITCODE -eq 0) {
                Write-BridgeStatusJson -State 'RUNNING' -Stage 'WAITING_HEALTHY' -Pct 92 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message "Verifying HTTPS gateway readiness on OSCAR $TargetVer..."
                if (Test-LocalHttpsReady -TargetDir $targetDir) {
                    $upgradeOk = $true
                }
            }
        } finally { $ErrorActionPreference = $prevPref }

        if ($upgradeOk) {
            if ($prevBackup -and (Test-Path -LiteralPath $prevBackup)) {
                Remove-Item -LiteralPath $prevBackup -Recurse -Force -ErrorAction SilentlyContinue
            }
            $newUpdateScript = Join-Path $targetDir 'oscar-update.ps1'
            if (Test-Path -LiteralPath $newUpdateScript) {
                & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $newUpdateScript write-completed-status -Version $TargetVer | Out-Null
            } else {
                Write-BridgeStatusJson -State 'COMPLETED' -Stage 'COMPLETED' -Pct 100 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message "Successfully upgraded OSCAR to $TargetVer."
            }
            Write-Host "OSCAR successfully upgraded to $TargetVer in $targetDir" -ForegroundColor Green
            return
        }

        Write-BridgeStatusJson -State 'RUNNING' -Stage 'ROLLING_BACK' -Pct 88 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message "Upgrade failed; automatically rolling back to previous OSCAR $(Get-OscarVersion) release..."
        $prevPref = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $ScriptRoot 'oscar-setup.ps1') upgrade | Out-Null
            if ($LASTEXITCODE -ne 0) {
                & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $ScriptRoot 'oscar-setup.ps1') start | Out-Null
            }
        } finally { $ErrorActionPreference = $prevPref }
        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($prevBackup -and (Test-Path -LiteralPath $prevBackup)) {
            Move-Item -LiteralPath $prevBackup -Destination $targetDir -Force -ErrorAction SilentlyContinue
        }
        Write-BridgeStatusJson -State 'ROLLED_BACK' -Stage 'ROLLED_BACK' -Pct 0 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message "Upgrade to $TargetVer failed; automatically restored previous OSCAR $(Get-OscarVersion) deployment."
        throw "Upgrade to $TargetVer failed; rolled back to $(Get-OscarVersion)."
    } catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -notmatch 'rolled back to') {
            Write-BridgeStatusJson -State 'FAILED' -Stage 'FAILED' -Pct 0 -TargetVer $TargetVer -ReqId $ReqId -JobAction $JobAction -Message $errMsg
        }
        throw
    } finally {
        Remove-Item -LiteralPath $workTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Enable-UiBridge {
    param([switch]$AutoInstall)
    Assert-Administrator
    $guiPref = (Get-EnvFileValue -Key 'OSCAR_GUI_UPDATE' -DefaultValue 'enabled').ToLowerInvariant()
    if ($AutoInstall -and ((Test-Path -LiteralPath $DisabledMarker) -or ($guiPref -eq 'disabled') -or ($guiPref -eq 'false'))) {
        Write-BridgeStatusJson -State 'IDLE' -Stage 'IDLE' -Pct 0
        return
    }
    if (-not $AutoInstall) {
        Remove-Item -LiteralPath $DisabledMarker -Force -ErrorAction SilentlyContinue
    }
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskAction = New-ScheduledTaskAction -Execute $psExe -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$SelfScript`" poll-bridge"
    $triggerBoot = New-ScheduledTaskTrigger -AtStartup
    $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
    # Register-ScheduledTask -Force updates the definition cleanly without killing any currently running upgrade process.
    Register-ScheduledTask -TaskName $AgentTaskName -Action $taskAction -Trigger @($triggerBoot, $triggerRepeat) -Settings $settings -User 'SYSTEM' -Force | Out-Null
    $existingStatus = Invoke-UpdateControlSh 'cat /var/lib/oscar/.moduledata/update-control/status.json 2>/dev/null || true'
    if (-not $AutoInstall -or [string]::IsNullOrWhiteSpace($existingStatus) -or $existingStatus -notmatch '"state"\s*:\s*"(RUNNING|COMPLETED|FAILED|ROLLED_BACK)"') {
        Write-BridgeStatusJson -State 'IDLE' -Stage 'IDLE' -Pct 0 -Message 'GUI System Update agent active.'
    }
    if (-not $AutoInstall) {
        Write-Host 'Enabled zero-login GUI System Update bridge (OSCAR-UpdateAgent).' -ForegroundColor Green
    }
}

function Disable-UiBridge {
    Assert-Administrator
    New-Item -ItemType Directory -Path (Split-Path -Parent $DisabledMarker) -Force | Out-Null
    [System.IO.File]::WriteAllText($DisabledMarker, 'disabled', $Utf8NoBom)
    Unregister-ScheduledTask -TaskName $AgentTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-BridgeStatusJson -State 'IDLE' -Stage 'IDLE' -Pct 0 -Message 'GUI System Update bridge disabled.'
    Write-Host 'Disabled OSCAR GUI System Update host bridge.'
}

function Invoke-PollBridge {
    Assert-Administrator
    $raw = Invoke-UpdateControlSh 'if [ -f /var/lib/oscar/.moduledata/update-control/request.json ]; then mv -f /var/lib/oscar/.moduledata/update-control/request.json /var/lib/oscar/.moduledata/update-control/request.processing && cat /var/lib/oscar/.moduledata/update-control/request.processing && rm -f /var/lib/oscar/.moduledata/update-control/request.processing; fi'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $hasStatus = Invoke-UpdateControlSh 'if [ -f /var/lib/oscar/.moduledata/update-control/status.json ]; then echo yes; fi'
        if ($hasStatus.Trim() -ne 'yes') {
            Write-BridgeStatusJson -State 'IDLE' -Stage 'IDLE' -Pct 0
        }
        return
    }
    $req = $raw | ConvertFrom-Json
    $reqId = [string]$req.requestId
    $reqAction = [string]$req.action
    $targetVer = [string]$req.targetVersion
    $expectedSha = [string]$req.expectedSha256
    $backupFirst = [bool]$req.createBackupFirst

    try {
        if ($reqAction -eq 'upgrade-github') {
            Invoke-SystemUpgrade -TargetVer $targetVer -ExpectedSha $expectedSha -CreateBackupFirst $backupFirst -ReqId $reqId -JobAction $reqAction
        } elseif ($reqAction -eq 'upgrade-staged') {
            $bundleLeaf = [System.IO.Path]::GetFileName([string]$req.bundleFileName)
            $tmpStaged = Join-Path $env:TEMP "oscar-staged-$([Guid]::NewGuid().ToString('N'))-$bundleLeaf"
            try {
                $ver = Get-OscarVersion
                & docker run --rm --network none -v oscar_oscar_state:/var/lib/oscar:ro -v "$($env:TEMP):/hosttmp" --entrypoint sh "oscar:$ver" -c "cp -f '/var/lib/oscar/.moduledata/update-control/staged/$bundleLeaf' '/hosttmp/$(Split-Path -Leaf $tmpStaged)'"
                if (-not (Test-Path -LiteralPath $tmpStaged)) {
                    throw "Staged bundle not found: $bundleLeaf"
                }
                Invoke-SystemUpgrade -TargetVer $targetVer -ZipSource $tmpStaged -ExpectedSha $expectedSha -CreateBackupFirst $backupFirst -ReqId $reqId -JobAction $reqAction
            } finally {
                Remove-Item -LiteralPath $tmpStaged -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warning "Poll-bridge job $reqId ended with failure: $($_.Exception.Message)"
    }
}

switch ($Action.ToLowerInvariant()) {
    'check' {
        $cur = Get-OscarVersion
        $rel = Get-LatestGitHubRelease
        $avail = Test-SemVerGreater -A $rel.Version -B $cur
        if ($Json) {
            $out = [ordered]@{
                currentVersion = $cur
                latestVersion = $rel.Version
                updateAvailable = $avail
                requiresGitHubLogin = $false
                downloadUrl = $rel.DownloadUrl
                expectedSha256 = $rel.ExpectedSha256
            }
            Write-Output ($out | ConvertTo-Json -Compress)
        } else {
            Write-Host "Current installed version: $cur"
            Write-Host "Latest GitHub release:     $($rel.Version) (zero GitHub login required)"
            if ($rel.ExpectedSha256) { Write-Host "Expected SHA-256:          $($rel.ExpectedSha256)" }
            if ($avail) {
                Write-Host "Status:                    UPDATE AVAILABLE ($cur -> $($rel.Version))" -ForegroundColor Yellow
                Write-Host 'Apply upgrade:             .\oscar.bat update apply'
            } else {
                Write-Host 'Status:                    UP TO DATE' -ForegroundColor Green
            }
        }
    }
    'apply' {
        $zipPath = $FromZip
        if ($Staged -and (-not $zipPath)) {
            throw 'Use GUI Apply on staged bundles or specify -FromZip <path-to-oscar.zip>.'
        }
        Invoke-SystemUpgrade -TargetVer $Version -ZipSource $zipPath -ExpectedSha $Sha256 -CreateBackupFirst ([bool]$BackupFirst) -ReqId "cli-$([int][double]::Parse((Get-Date -UFormat %s)))" -JobAction 'cli-upgrade'
    }
    'upgrade' {
        Invoke-SystemUpgrade -TargetVer $Version -ZipSource $FromZip -ExpectedSha $Sha256 -CreateBackupFirst ([bool]$BackupFirst) -ReqId 'cli' -JobAction 'cli-upgrade'
    }
    'status' {
        $cur = Get-OscarVersion
        $active = Test-BridgeAgentActive
        if ($Json) {
            $out = [ordered]@{
                currentVersion = $cur
                agentActive = $active
                releaseDir = $ScriptRoot
                availableDiskGib = (Get-AvailableDiskGib)
            }
            Write-Output ($out | ConvertTo-Json -Compress)
        } else {
            Write-Host 'OSCAR System Update Status'
            Write-Host "  Installed Version: $cur"
            Write-Host "  Release Directory: $ScriptRoot"
            Write-Host ("  GUI Update Agent:  " + $(if ($active) { 'ACTIVE' } else { 'DISABLED' }))
            Write-Host "  Free Disk Space:   $(Get-AvailableDiskGib) GiB"
        }
    }
    'enable-ui-bridge' { Enable-UiBridge }
    'install-agent' { Enable-UiBridge -AutoInstall }
    'disable-ui-bridge' { Disable-UiBridge }
    'poll-bridge' { Invoke-PollBridge }
    'run-once' { Invoke-PollBridge }
    'write-completed-status' {
        $v = if ($Version) { $Version } else { Get-OscarVersion }
        Write-BridgeStatusJson -State 'COMPLETED' -Stage 'COMPLETED' -Pct 100 -TargetVer $v -Message "Successfully upgraded OSCAR to $v."
    }
    default {
        Write-Host 'Usage:'
        Write-Host '  .\oscar.bat update check [-Json]'
        Write-Host '  .\oscar.bat update apply [-Version X.Y.Z] [-FromZip FILE] [-Sha256 HEX] [-BackupFirst]'
        Write-Host '  .\oscar.bat update status [-Json]'
        Write-Host '  .\oscar.bat update enable-ui-bridge | disable-ui-bridge'
    }
}
