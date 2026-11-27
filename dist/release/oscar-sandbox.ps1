#Requires -Version 5.1
<#
.SYNOPSIS
OSCAR Ephemeral Hands-On Training Sandbox & Guided Academy Manager (Windows 11 + WSL 2)
Launches an isolated :8444 training stack reusing the installed oscar:<version> and
oscar-postgis:<version> images with archive.enabled=false, disposable volumes, zero
writes to production PostgreSQL/Parquet/config.json, automatic TTL shutdown, and
instant complete wipe on stop or reset.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = 'help',
    [int]$Port = 8444,
    [int]$TtlMinutes = 120,
    [string]$Track = 'operator',
    [string]$AdminPassword = '',
    [switch]$AllowLowMemory,
    [switch]$Json,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$SelfScript = Join-Path $ScriptRoot 'oscar-sandbox.ps1'
$SandboxProject = 'oscar-sandbox'
$AgentTaskName = 'OSCAR-SandboxAgent'
$DisabledMarker = Join-Path $env:ProgramData 'OSCAR\sandbox-bridge.disabled'
$RuntimeDir = if ($env:OSCAR_SANDBOX_RUNTIME_DIR) { $env:OSCAR_SANDBOX_RUNTIME_DIR } else { Join-Path $env:ProgramData 'OSCAR\sandbox-runtime' }
$MinAvailRamMib = 3584
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    switch ($ExtraArgs[$i].ToLowerInvariant()) {
        '--port' { if ($i + 1 -lt $ExtraArgs.Count) { $Port = [int]$ExtraArgs[++$i] } }
        '--ttl-minutes' { if ($i + 1 -lt $ExtraArgs.Count) { $TtlMinutes = [int]$ExtraArgs[++$i] } }
        '--track' { if ($i + 1 -lt $ExtraArgs.Count) { $Track = [string]$ExtraArgs[++$i] } }
        '--admin-password' { if ($i + 1 -lt $ExtraArgs.Count) { $AdminPassword = [string]$ExtraArgs[++$i] } }
        '--allow-low-memory' { $AllowLowMemory = [switch]::Present }
        '--json' { $Json = [switch]::Present }
    }
}

function Invoke-DockerSafe {
    param([string[]]$DockerArgs, [string]$StdinScript = '')
    $prev = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ($StdinScript) {
            $out = ($StdinScript -replace "`r`n", "`n") | & docker @DockerArgs 2>$null
        } else {
            $out = & docker @DockerArgs 2>$null
        }
        return @{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
    } finally {
        $ErrorActionPreference = $prev
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

function Get-AvailableRamMib {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        return [int][math]::Floor($os.FreePhysicalMemory / 1024)
    } catch {
        return 8192
    }
}

function Test-SandboxRunning {
    $res = Invoke-DockerSafe @('ps', '--filter', "label=com.docker.compose.project=$SandboxProject", '--filter', 'label=com.docker.compose.service=gateway', '--format', '{{.ID}}')
    return [bool]($res.ExitCode -eq 0 -and $res.Output -and $res.Output.Trim().Length -gt 0)
}

function Get-RemoteSandboxInfo {
    $archiveDir = Get-EnvFileValue -Key 'OSCAR_ARCHIVE_DIR' -DefaultValue ''
    if (-not [string]::IsNullOrWhiteSpace($archiveDir)) {
        $storageRoot = Split-Path -Parent $archiveDir
    } else {
        $storageRoot = Join-Path (Split-Path -Parent $ScriptRoot) 'oscar-storage'
    }
    $octFile = Join-Path $storageRoot 'remote-access\octelium.env'
    $domain = ''
    $url = ''
    if (Test-Path -LiteralPath $octFile) {
        $enabled = (Get-EnvFileValue -Key 'OCTELIUM_ENABLED' -DefaultValue 'false' -FilePath $octFile).ToLowerInvariant()
        if ($enabled -eq 'true') {
            $domain = Get-EnvFileValue -Key 'OCTELIUM_DOMAIN' -DefaultValue '' -FilePath $octFile
            $svc = Get-EnvFileValue -Key 'OCTELIUM_SERVICE' -DefaultValue '' -FilePath $octFile
            if (-not [string]::IsNullOrWhiteSpace($domain) -and -not [string]::IsNullOrWhiteSpace($svc)) {
                $url = "https://$svc-sandbox.$domain"
            }
        }
    }
    return @{ Domain = $domain; Url = $url }
}

function Invoke-SandboxCompose {
    param([string[]]$ComposeArgs)
    $ra = Get-RemoteSandboxInfo
    $env:OSCAR_VERSION = Get-OscarVersion
    $env:OSCAR_TIMEZONE = Get-EnvFileValue -Key 'OSCAR_TIMEZONE' -DefaultValue 'UTC'
    $env:OSCAR_SANDBOX_RUNTIME_DIR = $RuntimeDir
    $env:OSCAR_WEBAUTHN_RP_ID = $ra.Domain
    & docker compose --project-name $SandboxProject --project-directory $ScriptRoot --file (Join-Path $ScriptRoot 'compose.sandbox.yaml') @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose ($SandboxProject) exited with code $LASTEXITCODE"
    }
}

function New-RandomHex {
    param([int]$Bytes = 16)
    $buf = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buf)
    $rng.Dispose()
    return ($buf | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Invoke-SandboxControlSh {
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
            $tmpIn = Join-Path $env:TEMP "oscar-sbctrl-in-$([Guid]::NewGuid().ToString('N')).tmp"
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
                return ([string](& cmd.exe /c "type `"$tmpIn`" | docker run --rm --label com.docker.compose.project=oscar-sandbox-bridge -i --network none --user 10001:10001 -v oscar_oscar_state:/var/lib/oscar --entrypoint sh oscar:$ver -eu -c `"$ShCmd`" 2>nul"))
            }
            return ([string](& docker run --rm --label com.docker.compose.project=oscar-sandbox-bridge --network none --user 10001:10001 -v oscar_oscar_state:/var/lib/oscar --entrypoint sh "oscar:$ver" -eu -c $ShCmd 2>$null))
        } finally { $ErrorActionPreference = $prev }
    } finally {
        if ($tmpIn) { Remove-Item -LiteralPath $tmpIn -Force -ErrorAction SilentlyContinue }
    }
}

function Test-BridgeAgentActive {
    try {
        $t = Get-ScheduledTask -TaskName $AgentTaskName -ErrorAction SilentlyContinue
        return [bool]($null -ne $t -and [string]$t.State -ne 'Disabled')
    } catch {
        return $false
    }
}

function Write-BridgeStatusJson {
    param($ActiveJob = $null)
    try {
        $running = Test-SandboxRunning
        $metaFile = Join-Path $RuntimeDir 'sandbox.meta'
        $p = 8444
        $t = 120
        $exp = ''
        if (Test-Path -LiteralPath $metaFile) {
            $p = [int](Get-EnvFileValue -Key 'HTTPS_PORT' -DefaultValue '8444' -FilePath $metaFile)
            $t = [int](Get-EnvFileValue -Key 'TTL_MINUTES' -DefaultValue '120' -FilePath $metaFile)
            $exp = Get-EnvFileValue -Key 'EXPIRES_AT' -DefaultValue '' -FilePath $metaFile
        }
        $ra = Get-RemoteSandboxInfo
        $statusObj = [ordered]@{
            agentActive     = (Test-BridgeAgentActive)
            sandboxRunning  = $running
            httpsPort       = $p
            ttlMinutes      = $t
            availableRamMib = (Get-AvailableRamMib)
        }
        if (-not [string]::IsNullOrWhiteSpace($ra.Domain)) {
            $statusObj['remoteDomain'] = $ra.Domain
        }
        if (-not [string]::IsNullOrWhiteSpace($ra.Url)) {
            $statusObj['remoteSandboxUrl'] = $ra.Url
        }
        if (-not [string]::IsNullOrWhiteSpace($exp)) {
            $statusObj['expiresAt'] = $exp
        }
        if ($null -ne $ActiveJob) {
            $statusObj['activeJob'] = $ActiveJob
        }
        $json = $statusObj | ConvertTo-Json -Depth 5
        Invoke-SandboxControlSh 'mkdir -p /var/lib/oscar/.moduledata/sandbox-control && chmod 0700 /var/lib/oscar/.moduledata/sandbox-control && cat >/var/lib/oscar/.moduledata/sandbox-control/.status.tmp && mv -f /var/lib/oscar/.moduledata/sandbox-control/.status.tmp /var/lib/oscar/.moduledata/sandbox-control/status.json' $json | Out-Null
    } catch {}
}

function Get-SandboxNowEpoch {
    if ($env:OSCAR_SANDBOX_NOW_EPOCH -and $env:OSCAR_SANDBOX_NOW_EPOCH -match '^\d+$') {
        return [int64]$env:OSCAR_SANDBOX_NOW_EPOCH
    }
    $epochOrigin = New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    return [int64][Math]::Floor(([DateTime]::UtcNow - $epochOrigin).TotalSeconds)
}

function Get-SandboxExpiryEpoch {
    $metaFile = Join-Path $RuntimeDir 'sandbox.meta'
    if (Test-Path -LiteralPath $metaFile) {
        $startedRaw = Get-EnvFileValue -Key 'STARTED_EPOCH' -DefaultValue '' -FilePath $metaFile
        $ttlRaw = Get-EnvFileValue -Key 'TTL_MINUTES' -DefaultValue '' -FilePath $metaFile
        if ($startedRaw -match '^\d+$' -and $ttlRaw -match '^\d+$') {
            $startedVal = [int64]$startedRaw
            $ttlVal = [int64]$ttlRaw
            if ($startedVal -gt 0 -and $ttlVal -gt 0) {
                return ($startedVal + ($ttlVal * 60))
            }
        }
        $expRaw = Get-EnvFileValue -Key 'EXPIRES_AT' -DefaultValue '' -FilePath $metaFile
        if (-not [string]::IsNullOrWhiteSpace($expRaw)) {
            try {
                $parsed = [DateTime]::Parse($expRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                $epochOrigin = New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
                return [int64][Math]::Floor(($parsed.ToUniversalTime() - $epochOrigin).TotalSeconds)
            } catch {}
        }
    }

    # Fallback: read TTL metadata directly from the running oscar sandbox container
    $cidRes = Invoke-DockerSafe @('ps', '--filter', "label=com.docker.compose.project=$SandboxProject", '--filter', 'label=com.docker.compose.service=oscar', '--format', '{{.ID}}')
    if ($cidRes.ExitCode -eq 0 -and $cidRes.Output -and $cidRes.Output.Trim().Length -gt 0) {
        $cid = ($cidRes.Output -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1).Trim()
        if ($cid) {
            $envRes = Invoke-DockerSafe @('inspect', '--format', '{{range .Config.Env}}{{println .}}{{end}}', $cid)
            if ($envRes.ExitCode -eq 0 -and $envRes.Output) {
                $startedVal = [int64]0
                $ttlVal = [int64]0
                foreach ($line in ($envRes.Output -split '\r?\n')) {
                    if ($line -match '^OSCAR_SANDBOX_STARTED_EPOCH_SEC=(\d+)$') { $startedVal = [int64]$Matches[1] }
                    elseif ($line -match '^OSCAR_SANDBOX_TTL_MINUTES=(\d+)$') { $ttlVal = [int64]$Matches[1] }
                }
                if ($startedVal -gt 0 -and $ttlVal -gt 0) {
                    return ($startedVal + ($ttlVal * 60))
                }
            }
        }
    }
    return $null
}

function Invoke-EnforceSandboxExpiry {
    if (-not (Test-SandboxRunning)) { return $false }
    $expEpoch = Get-SandboxExpiryEpoch
    if ($null -eq $expEpoch) { return $false }
    $nowEpoch = Get-SandboxNowEpoch
    if ($nowEpoch -ge $expEpoch) {
        Stop-SandboxStack -Reason 'Training Sandbox auto-shutdown TTL expired; ephemeral volumes flushed.'
        return $true
    }
    return $false
}

function Invoke-BridgeTick {
    param([switch]$StatusOnly)
    $reqRaw = Invoke-SandboxControlSh 'if [ -f /var/lib/oscar/.moduledata/sandbox-control/request.json ]; then mv -f /var/lib/oscar/.moduledata/sandbox-control/request.json /var/lib/oscar/.moduledata/sandbox-control/.processing.json && touch /var/lib/oscar/.moduledata/sandbox-control/.active-job.lock && cat /var/lib/oscar/.moduledata/sandbox-control/.processing.json && rm -f /var/lib/oscar/.moduledata/sandbox-control/.processing.json; fi'
    if ([string]::IsNullOrWhiteSpace($reqRaw)) {
        if ($StatusOnly) {
            $locked = Invoke-SandboxControlSh 'if [ -f /var/lib/oscar/.moduledata/sandbox-control/.active-job.lock ]; then age=$(( $(date +%s) - $(stat -c %Y /var/lib/oscar/.moduledata/sandbox-control/.active-job.lock 2>/dev/null || echo 0) )); if [ "$age" -ge 0 ] && [ "$age" -lt 180 ]; then printf LOCKED; else rm -f /var/lib/oscar/.moduledata/sandbox-control/.active-job.lock; fi; fi'
            if ($locked -ne 'LOCKED') {
                if (-not (Invoke-EnforceSandboxExpiry)) {
                    Write-BridgeStatusJson $null
                }
            }
        }
        return
    }
    $req = $reqRaw | ConvertFrom-Json
    $act = ([string]$req.action).ToLowerInvariant()
    $reqId = [string]$req.requestId
    $reqPort = if ($null -ne $req.PSObject.Properties['httpsPort'] -and $req.httpsPort) { [int]$req.httpsPort } else { 8444 }
    $reqTtl = if ($null -ne $req.PSObject.Properties['ttlMinutes'] -and $req.ttlMinutes) { [int]$req.ttlMinutes } else { 120 }
    $startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    Write-BridgeStatusJson ([ordered]@{
        requestId = $reqId
        action    = $act
        state     = 'RUNNING'
        startedAt = $startedAt
        message   = "Executing sandbox '$act'..."
    })

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        switch ($act) {
            'start' {
                if ((Test-SandboxRunning) -and (-not (Invoke-EnforceSandboxExpiry))) {
                    Write-BridgeStatusJson ([ordered]@{
                        requestId = $reqId; action = 'start'; state = 'COMPLETED'; startedAt = $startedAt
                        message = "Training Sandbox already running on port $reqPort."
                    })
                    return
                }
                $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try {
                    & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SelfScript start -Port $reqPort -TtlMinutes $reqTtl 2>&1 | Out-Null
                    $rc = $LASTEXITCODE
                } catch { $rc = 1 } finally { $ErrorActionPreference = $prev }
                $st = if ($rc -eq 0) { 'COMPLETED' } else { 'FAILED' }
                $msg = if ($rc -eq 0) { "Training Sandbox ready on port $reqPort." } else { 'Sandbox start failed; check free RAM or run .\oscar.bat sandbox start.' }
                Write-BridgeStatusJson ([ordered]@{ requestId = $reqId; action = 'start'; state = $st; startedAt = $startedAt; message = $msg })
            }
            'reset' {
                $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try {
                    & $psExe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SelfScript reset -Port $reqPort -TtlMinutes $reqTtl 2>&1 | Out-Null
                    $rc = $LASTEXITCODE
                } catch { $rc = 1 } finally { $ErrorActionPreference = $prev }
                $st = if ($rc -eq 0) { 'COMPLETED' } else { 'FAILED' }
                $msg = if ($rc -eq 0) { "Training Sandbox reset and ready on port $reqPort." } else { 'Sandbox reset failed.' }
                Write-BridgeStatusJson ([ordered]@{ requestId = $reqId; action = 'reset'; state = $st; startedAt = $startedAt; message = $msg })
            }
            'stop' {
                Stop-SandboxStack
                Write-BridgeStatusJson ([ordered]@{ requestId = $reqId; action = 'stop'; state = 'COMPLETED'; startedAt = $startedAt; message = 'Training Sandbox stopped and flushed.' })
            }
            default {
                Write-BridgeStatusJson ([ordered]@{ requestId = $reqId; action = $act; state = 'COMPLETED'; startedAt = $startedAt; message = 'Refreshed status.' })
            }
        }
    } finally {
        Invoke-SandboxControlSh 'rm -f /var/lib/oscar/.moduledata/sandbox-control/.active-job.lock' | Out-Null
    }
}

function Invoke-BridgeWatch {
    $lastStatusAt = [DateTime]::MinValue
    while ($true) {
        $doStatus = (((Get-Date) - $lastStatusAt).TotalSeconds -ge 20)
        try {
            Invoke-BridgeTick -StatusOnly:$doStatus
            if ($doStatus) { $lastStatusAt = Get-Date }
        } catch {}
        Start-Sleep -Seconds 3
    }
}

function Enable-UiBridge {
    param([switch]$AutoInstall)
    if ($AutoInstall) {
        $pref = (Get-EnvFileValue -Key 'OSCAR_SANDBOX_UI_BRIDGE' -DefaultValue 'enabled').ToLowerInvariant()
        if ((Test-Path -LiteralPath $DisabledMarker) -or $pref -eq 'disabled' -or $env:OSCAR_SANDBOX_SKIP_TASK -eq '1') {
            Write-BridgeStatusJson $null
            return
        }
    } else {
        Remove-Item -LiteralPath $DisabledMarker -Force -ErrorAction SilentlyContinue
    }
    if ($env:OSCAR_SANDBOX_SKIP_TASK -ne '1') {
        if (Get-ScheduledTask -TaskName $AgentTaskName -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $AgentTaskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $AgentTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        try {
            Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'oscar-sandbox\.ps1' -and $_.CommandLine -match 'agent-watch' } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch {}
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $actionObj = New-ScheduledTaskAction -Execute $psExe -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$SelfScript`" agent-watch" -WorkingDirectory $ScriptRoot
        $triggerBoot = New-ScheduledTaskTrigger -AtStartup
        $triggerKeepAlive = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -Priority 8
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $AgentTaskName -Action $actionObj -Trigger @($triggerBoot, $triggerKeepAlive) -Settings $settings -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName $AgentTaskName -ErrorAction SilentlyContinue
    }
    Write-BridgeStatusJson $null
    if (-not $AutoInstall) {
        Write-Host 'Enabled 1-click Training Sandbox launch in Guided Walkthrough & Help (?).' -ForegroundColor Green
    }
}

function Disable-UiBridge {
    $markerDir = Split-Path -Parent $DisabledMarker
    if (-not (Test-Path -LiteralPath $markerDir)) { New-Item -ItemType Directory -Path $markerDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($DisabledMarker, "disabled`n", $Utf8NoBom)
    if (Get-ScheduledTask -TaskName $AgentTaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $AgentTaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $AgentTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    Write-BridgeStatusJson $null
    Write-Host 'Disabled Training Sandbox browser UI bridge.' -ForegroundColor Yellow
}

function Stop-SandboxStack {
    param([string]$Reason = '')
    try { Unregister-ScheduledTask -TaskName 'OSCAR-Sandbox-Expiry' -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    if (Test-Path -LiteralPath $RuntimeDir) {
        $prev = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $ra = Get-RemoteSandboxInfo
            $env:OSCAR_VERSION = Get-OscarVersion
            $env:OSCAR_TIMEZONE = Get-EnvFileValue -Key 'OSCAR_TIMEZONE' -DefaultValue 'UTC'
            $env:OSCAR_SANDBOX_RUNTIME_DIR = $RuntimeDir
            $env:OSCAR_WEBAUTHN_RP_ID = $ra.Domain
            & docker compose --project-name $SandboxProject --project-directory $ScriptRoot --file (Join-Path $ScriptRoot 'compose.sandbox.yaml') down -v --remove-orphans 2>$null | Out-Null
        } catch {} finally {
            $ErrorActionPreference = $prev
        }
    }
    $psRes = Invoke-DockerSafe @('ps', '-aq', '--filter', "label=com.docker.compose.project=$SandboxProject")
    if ($psRes.Output -and $psRes.Output.Trim().Length -gt 0) {
        $containerIds = @($psRes.Output -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 })
        [void](Invoke-DockerSafe (@('rm', '-f') + $containerIds))
    }
    [void](Invoke-DockerSafe @('volume', 'rm', '-f', 'oscar_sandbox_state', 'oscar_sandbox_pg'))
    [void](Invoke-DockerSafe @('network', 'rm', "${SandboxProject}_sandbox_frontend", "${SandboxProject}_sandbox_database"))
    if (Test-Path -LiteralPath $RuntimeDir) {
        Remove-Item -LiteralPath $RuntimeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-BridgeStatusJson ([ordered]@{
            requestId = ''
            action    = 'stop'
            state     = 'COMPLETED'
            message   = $Reason
        })
    } else {
        Write-BridgeStatusJson $null
    }
}

function Start-SandboxStack {
    if ($Port -lt 1024 -or $Port -gt 65535 -or $Port -eq 443 -or $Port -eq 8443) {
        throw "Sandbox HTTPS port must be between 1024 and 65535 (excluding 443 and 8443)."
    }
    if ($TtlMinutes -lt 5 -or $TtlMinutes -gt 1440) {
        throw "Sandbox -TtlMinutes must be between 5 and 1440."
    }
    $prodPort = [int](Get-EnvFileValue -Key 'OSCAR_HTTPS_PORT' -DefaultValue '443')
    if ($Port -eq $prodPort) {
        throw "Sandbox port ($Port) must not collide with operational OSCAR_HTTPS_PORT ($prodPort)."
    }

    $availMib = Get-AvailableRamMib
    if (-not $AllowLowMemory -and $availMib -lt $MinAvailRamMib) {
        throw "Insufficient free RAM for Training Sandbox (${availMib} MiB available; >= ${MinAvailRamMib} MiB required). Pass -AllowLowMemory to override."
    }

    $ver = Get-OscarVersion
    $imgCheck = Invoke-DockerSafe @('image', 'inspect', "oscar:$ver")
    if ($imgCheck.ExitCode -ne 0) {
        throw "Docker image oscar:$ver is not loaded yet. Run .\oscar.bat init first."
    }

    Stop-SandboxStack

    $secretsDir = Join-Path $RuntimeDir 'secrets'
    $tlsDir = Join-Path $RuntimeDir 'tls'
    New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $tlsDir -Force | Out-Null

    [System.IO.File]::WriteAllText((Join-Path $secretsDir 'oscar-db-password.txt'), (New-RandomHex 24) + "`n", $Utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $secretsDir 'postgres-bootstrap-password.txt'), (New-RandomHex 24) + "`n", $Utf8NoBom)

    $printedCreds = ''
    if ($AdminPassword) {
        [System.IO.File]::WriteAllText((Join-Path $secretsDir 'oscar-admin-password.txt'), $AdminPassword + "`n", $Utf8NoBom)
        $printedCreds = '(custom -AdminPassword supplied)'
    } else {
        # Extract existing BasicSecurityRealmConfig PBKDF2 hash from oscar_oscar_state via a tiny read-only oscar container probe
        $awkStdin = 'if [ -f /prod/config.json ]; then awk ''/"objClass":[ \t]*"org\.sensorhub\.impl\.security\.BasicSecurityRealmConfig"/ { f=1 } f && /"password":[ \t]*"/ { sub(/^.*"password":[ \t]*"/, ""); sub(/".*$/, ""); if ($0 != "" && $0 != "__INITIAL_ADMIN_PASSWORD__") { print; exit } }'' /prod/config.json; fi'
        $hashRes = Invoke-DockerSafe -DockerArgs @('run', '--rm', '-i', '-v', 'oscar_oscar_state:/prod:ro', '--user', 'root', '--entrypoint', '/bin/sh', "oscar:$ver") -StdinScript $awkStdin
        $extractedHash = $hashRes.Output
        if ($extractedHash -and $extractedHash.Trim().Length -gt 0) {
            [System.IO.File]::WriteAllText((Join-Path $secretsDir 'oscar-admin-password.txt'), "# PBKDF2_PREENCODED:$($extractedHash.Trim())`n", $Utf8NoBom)
            $printedCreds = '(same credentials & Passkeys as your operational OSCAR site)'
        } else {
            $genPw = "Sandbox-$(New-RandomHex 6)"
            [System.IO.File]::WriteAllText((Join-Path $secretsDir 'oscar-admin-password.txt'), "$genPw`n", $Utf8NoBom)
            $printedCreds = "admin / $genPw"
        }
    }

    $prodCert = Join-Path $ScriptRoot 'tls\server.crt'
    $prodKey = Join-Path $ScriptRoot 'tls\server.key'
    $altCert = Join-Path $ScriptRoot 'tls\certificate.pem'
    $altKey = Join-Path $ScriptRoot 'tls\private-key.pem'
    if ((Test-Path -LiteralPath $prodCert) -and (Test-Path -LiteralPath $prodKey)) {
        Copy-Item -LiteralPath $prodCert -Destination (Join-Path $tlsDir 'certificate.pem') -Force
        Copy-Item -LiteralPath $prodKey -Destination (Join-Path $tlsDir 'private-key.pem') -Force
    } elseif ((Test-Path -LiteralPath $altCert) -and (Test-Path -LiteralPath $altKey)) {
        Copy-Item -LiteralPath $altCert -Destination (Join-Path $tlsDir 'certificate.pem') -Force
        Copy-Item -LiteralPath $altKey -Destination (Join-Path $tlsDir 'private-key.pem') -Force
    } else {
        throw "TLS certificate files not found in tls\ (server.crt / server.key). Run .\oscar.bat init first."
    }

    [void](Invoke-DockerSafe @('volume', 'create', 'oscar_sandbox_state'))
    [void](Invoke-DockerSafe @('volume', 'create', 'oscar_sandbox_pg'))
    [void](Invoke-DockerSafe @('run', '--rm', '-v', 'oscar_sandbox_state:/sb', '--user', 'root', '--entrypoint', '/bin/sh', "oscar:$ver", '-c', 'chown 10001:10001 /sb && chmod 0700 /sb'))
    if (-not $AdminPassword) {
        [void](Invoke-DockerSafe @('run', '--rm', '-v', 'oscar_oscar_state:/prod:ro', '-v', 'oscar_sandbox_state:/sb', '--user', 'root', '--entrypoint', '/bin/sh', "oscar:$ver", '-c', 'chown 10001:10001 /sb && chmod 0700 /sb && install -d -m 0700 -o 10001 -g 10001 /sb/.moduledata && if [ -f /prod/.moduledata/oscar-identity.json ]; then cp -f /prod/.moduledata/oscar-identity.json /sb/.moduledata/oscar-identity.json && chown 10001:10001 /sb/.moduledata/oscar-identity.json && chmod 0600 /sb/.moduledata/oscar-identity.json; fi && if [ -f /prod/config.json ]; then java -classpath "/opt/oscar/lib/*" com.botts.impl.service.oscar.sandbox.SandboxAuthConfigSeeder extract /prod/config.json /sb/.moduledata/sandbox-auth-seed.json >/dev/null 2>&1 || true; if [ -f /sb/.moduledata/sandbox-auth-seed.json ]; then chown 10001:10001 /sb/.moduledata/sandbox-auth-seed.json && chmod 0600 /sb/.moduledata/sandbox-auth-seed.json; fi; fi'))
    }

    $utcNow = [DateTime]::UtcNow
    $epochOrigin = New-Object DateTime(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    $nowEpoch = [int][Math]::Floor(($utcNow - $epochOrigin).TotalSeconds)
    $expUtc = $utcNow.AddMinutes($TtlMinutes).ToString('yyyy-MM-ddTHH:mm:ssZ')
    [System.IO.File]::WriteAllLines(
        (Join-Path $RuntimeDir 'sandbox.meta'),
        @(
            "HTTPS_PORT=$Port",
            "TTL_MINUTES=$TtlMinutes",
            "STARTED_EPOCH=$nowEpoch",
            "EXPIRES_AT=$expUtc",
            "INITIAL_TRACK=$Track"
        ),
        $Utf8NoBom
    )

    $env:OSCAR_SANDBOX_PORT = "$Port"
    $env:OSCAR_SANDBOX_TTL_MINUTES = "$TtlMinutes"
    $env:OSCAR_SANDBOX_STARTED_EPOCH_SEC = "$nowEpoch"
    $env:OSCAR_SANDBOX_INITIAL_TRACK = $Track
    Invoke-SandboxCompose @('up', '--detach', '--no-build', '--pull', 'never', '--wait', '--wait-timeout', '180')

    try {
        $expireAtLocal = $utcNow.AddMinutes($TtlMinutes).ToLocalTime()
        if ($expireAtLocal -le (Get-Date).AddSeconds(5)) {
            $expireAtLocal = (Get-Date).AddSeconds(5)
        }
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $taskAction = New-ScheduledTaskAction -Execute $psExe -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$SelfScript`" stop" -WorkingDirectory $ScriptRoot
        $taskTrigger = New-ScheduledTaskTrigger -Once -At $expireAtLocal
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'OSCAR-Sandbox-Expiry' -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Force | Out-Null
    } catch {}
    Write-BridgeStatusJson $null

    $hostName = Get-EnvFileValue -Key 'OSCAR_HOSTNAME' -DefaultValue 'localhost'
    $ra = Get-RemoteSandboxInfo
    Write-Host "`n========================================================================" -ForegroundColor Yellow
    Write-Host "OSCAR $ver - Hands-On Training Sandbox & Guided Academy ACTIVE" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "  Sandbox URL:      https://${hostName}:${Port}"
    if (-not [string]::IsNullOrWhiteSpace($ra.Url)) {
        Write-Host "  Remote Tunnel:    $($ra.Url) (Let's Encrypt + Passkeys)"
    }
    Write-Host "  Credentials:      $printedCreds"
    Write-Host "  Initial Track:    $Track (switchable in-UI: Operator / Supervisor / Admin)"
    Write-Host "  Auto-Flush TTL:   $TtlMinutes minutes ($expUtc)"
    Write-Host "  Isolation:        ZERO mounts to oscar_postgres_data, oscar_oscar_state,"
    Write-Host "                    or Parquet archive (archive.enabled = false)"
    Write-Host "  Stop & Flush:     .\oscar.bat sandbox stop"
    Write-Host "========================================================================`n" -ForegroundColor Yellow
}

switch ($Action.ToLowerInvariant()) {
    'start' { Start-SandboxStack }
    'reset' { Start-SandboxStack }
    'stop' {
        Stop-SandboxStack
        Write-Host 'OSCAR Training Sandbox stopped and all ephemeral practice volumes were completely flushed.' -ForegroundColor Green
    }
    'status' {
        $running = Test-SandboxRunning
        $ra = Get-RemoteSandboxInfo
        $metaFile = Join-Path $RuntimeDir 'sandbox.meta'
        $p = $Port
        $t = $TtlMinutes
        $exp = ''
        if (Test-Path -LiteralPath $metaFile) {
            $p = [int](Get-EnvFileValue -Key 'HTTPS_PORT' -DefaultValue '8444' -FilePath $metaFile)
            $t = [int](Get-EnvFileValue -Key 'TTL_MINUTES' -DefaultValue '120' -FilePath $metaFile)
            $exp = Get-EnvFileValue -Key 'EXPIRES_AT' -DefaultValue '' -FilePath $metaFile
        }
        if ($Json) {
            $obj = @{
                sandboxRunning = $running
                httpsPort = $p
                ttlMinutes = $t
                expiresAt = $exp
                availableRamMib = (Get-AvailableRamMib)
                remoteSandboxUrl = $ra.Url
            }
            Write-Output ($obj | ConvertTo-Json -Compress)
        } elseif ($running) {
            Write-Host "Training Sandbox: RUNNING on HTTPS port $p (expires: $exp)" -ForegroundColor Green
            if (-not [string]::IsNullOrWhiteSpace($ra.Url)) {
                Write-Host "Remote Sandbox URL: $($ra.Url)" -ForegroundColor Cyan
            }
            & docker ps --filter "label=com.docker.compose.project=$SandboxProject" --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
        } else {
            Write-Host 'Training Sandbox: STOPPED (0 sandbox containers, 0 sandbox volumes)'
        }
    }
    'enable-ui-bridge' {
        Enable-UiBridge
    }
    'install-agent' {
        Enable-UiBridge -AutoInstall
    }
    'disable-ui-bridge' {
        Disable-UiBridge
    }
    'poll-bridge' {
        Invoke-BridgeTick -StatusOnly
    }
    'agent-watch' {
        Invoke-BridgeWatch
    }
    default {
        Write-Host 'Usage:'
        Write-Host '  .\oscar.bat sandbox start [-Port 8444] [-TtlMinutes 120] [-Track operator|supervisor|administrator]'
        Write-Host '  .\oscar.bat sandbox stop'
        Write-Host '  .\oscar.bat sandbox reset [-Port 8444] [-TtlMinutes 120]'
        Write-Host '  .\oscar.bat sandbox status [-Json]'
        Write-Host '  .\oscar.bat sandbox enable-ui-bridge | disable-ui-bridge'
    }
}
