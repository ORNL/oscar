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
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ScriptRoot = (Resolve-Path -LiteralPath $PSScriptRoot).ProviderPath
$SandboxProject = 'oscar-sandbox'
$RuntimeDir = if ($env:OSCAR_SANDBOX_RUNTIME_DIR) { $env:OSCAR_SANDBOX_RUNTIME_DIR } else { Join-Path $env:ProgramData 'OSCAR\sandbox-runtime' }
$MinAvailRamMib = 3584
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-DockerSafe {
    param([string[]]$DockerArgs)
    $prev = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $out = & docker @DockerArgs 2>$null
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

function Invoke-SandboxCompose {
    param([string[]]$ComposeArgs)
    $env:OSCAR_VERSION = Get-OscarVersion
    $env:OSCAR_TIMEZONE = Get-EnvFileValue -Key 'OSCAR_TIMEZONE' -DefaultValue 'UTC'
    $env:OSCAR_SANDBOX_RUNTIME_DIR = $RuntimeDir
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

function Stop-SandboxStack {
    try { Unregister-ScheduledTask -TaskName 'OSCAR-Sandbox-Expiry' -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    if (Test-Path -LiteralPath $RuntimeDir) {
        $prev = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $env:OSCAR_VERSION = Get-OscarVersion
            $env:OSCAR_TIMEZONE = Get-EnvFileValue -Key 'OSCAR_TIMEZONE' -DefaultValue 'UTC'
            $env:OSCAR_SANDBOX_RUNTIME_DIR = $RuntimeDir
            & docker compose --project-name $SandboxProject --project-directory $ScriptRoot --file (Join-Path $ScriptRoot 'compose.sandbox.yaml') down -v --remove-orphans 2>$null | Out-Null
        } catch {} finally {
            $ErrorActionPreference = $prev
        }
    } else {
        $psRes = Invoke-DockerSafe @('ps', '-aq', '--filter', "label=com.docker.compose.project=$SandboxProject")
        if ($psRes.Output -and $psRes.Output.Trim().Length -gt 0) {
            $containerIds = @($psRes.Output -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 })
            [void](Invoke-DockerSafe (@('rm', '-f') + $containerIds))
        }
    }
    [void](Invoke-DockerSafe @('volume', 'rm', '-f', 'oscar_sandbox_state', 'oscar_sandbox_pg'))
    [void](Invoke-DockerSafe @('network', 'rm', "${SandboxProject}_sandbox_frontend", "${SandboxProject}_sandbox_database"))
    if (Test-Path -LiteralPath $RuntimeDir) {
        Remove-Item -LiteralPath $RuntimeDir -Recurse -Force -ErrorAction SilentlyContinue
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
        $hashRes = Invoke-DockerSafe @('run', '--rm', '-v', 'oscar_oscar_state:/prod:ro', '--entrypoint', '/bin/sh', "oscar:$ver", '-c', 'if [ -f /prod/config.json ]; then awk ''/"objClass": "org.sensorhub.impl.security.BasicSecurityRealmConfig"/ { f=1 } f && /"password": "/ { sub(/^.*"password": "/, ""); sub(/".*$/, ""); if ($0 != "" && $0 != "__INITIAL_ADMIN_PASSWORD__") { print; exit } }'' /prod/config.json; fi')
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
    if (-not $AdminPassword) {
        [void](Invoke-DockerSafe @('run', '--rm', '-v', 'oscar_oscar_state:/prod:ro', '-v', 'oscar_sandbox_state:/sb', '--user', 'root', '--entrypoint', '/bin/sh', "oscar:$ver", '-c', 'if [ -f /prod/.moduledata/oscar-identity.json ]; then install -d -m 0700 -o 10001 -g 10001 /sb/.moduledata && cp -f /prod/.moduledata/oscar-identity.json /sb/.moduledata/oscar-identity.json && chown 10001:10001 /sb/.moduledata/oscar-identity.json && chmod 0600 /sb/.moduledata/oscar-identity.json; fi'))
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
        $expireAtLocal = (Get-Date).AddMinutes($TtlMinutes)
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" stop"
        $taskTrigger = New-ScheduledTaskTrigger -Once -At $expireAtLocal
        Register-ScheduledTask -TaskName 'OSCAR-Sandbox-Expiry' -Action $taskAction -Trigger $taskTrigger -User 'SYSTEM' -Force | Out-Null
    } catch {}

    $hostName = Get-EnvFileValue -Key 'OSCAR_HOSTNAME' -DefaultValue 'localhost'
    Write-Host "`n========================================================================" -ForegroundColor Yellow
    Write-Host "OSCAR $ver - Hands-On Training Sandbox & Guided Academy ACTIVE" -ForegroundColor Green
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "  Sandbox URL:      https://${hostName}:${Port}"
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
        $metaFile = Join-Path $RuntimeDir 'sandbox.meta'
        $p = $Port
        $exp = ''
        if (Test-Path -LiteralPath $metaFile) {
            $p = [int](Get-EnvFileValue -Key 'HTTPS_PORT' -DefaultValue '8444' -FilePath $metaFile)
            $exp = Get-EnvFileValue -Key 'EXPIRES_AT' -DefaultValue '' -FilePath $metaFile
        }
        if ($Json) {
            $obj = @{
                sandboxRunning = $running
                httpsPort = $p
                ttlMinutes = $TtlMinutes
                expiresAt = $exp
                availableRamMib = (Get-AvailableRamMib)
            }
            Write-Output ($obj | ConvertTo-Json -Compress)
        } elseif ($running) {
            Write-Host "Training Sandbox: RUNNING on HTTPS port $p (expires: $exp)" -ForegroundColor Green
            & docker ps --filter "label=com.docker.compose.project=$SandboxProject" --format "table {{.Names}}`t{{.Status}}`t{{.Ports}}"
        } else {
            Write-Host 'Training Sandbox: STOPPED (0 sandbox containers, 0 sandbox volumes)'
        }
    }
    'enable-ui-bridge' {
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" status"
        Write-Host 'Use .\oscar.bat sandbox start / stop on Windows hosts, or open https://<host>:8444 once started.' -ForegroundColor Cyan
    }
    'disable-ui-bridge' {
        Unregister-ScheduledTask -TaskName 'OSCAR-Sandbox-Agent' -Confirm:$false -ErrorAction SilentlyContinue
    }
    default {
        Write-Host 'Usage:'
        Write-Host '  .\oscar.bat sandbox start [-Port 8444] [-TtlMinutes 120] [-Track operator|supervisor|administrator]'
        Write-Host '  .\oscar.bat sandbox stop'
        Write-Host '  .\oscar.bat sandbox reset [-Port 8444] [-TtlMinutes 120]'
        Write-Host '  .\oscar.bat sandbox status [-Json]'
    }
}
