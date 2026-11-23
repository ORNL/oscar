[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [string]$Subcommand = 'help',

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Fail([string]$Message) {
    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

function Get-EnvFileValue([string]$FilePath, [string]$Key) {
    if (-not (Test-Path -LiteralPath $FilePath)) { return '' }
    foreach ($line in [System.IO.File]::ReadAllLines($FilePath)) {
        $idx = $line.IndexOf('=')
        if ($idx -gt 0 -and $line.Substring(0, $idx) -ceq $Key) {
            return $line.Substring($idx + 1)
        }
    }
    return ''
}

function Get-RpmProxyDir {
    if (-not [string]::IsNullOrWhiteSpace($env:OSCAR_RPM_PROXY_STATE_DIR)) {
        return $env:OSCAR_RPM_PROXY_STATE_DIR
    }
    $envFile = Join-Path $ScriptRoot '.env'
    $archiveDir = Get-EnvFileValue $envFile 'OSCAR_ARCHIVE_DIR'
    if (-not [string]::IsNullOrWhiteSpace($archiveDir)) {
        $storageRoot = Split-Path -Parent $archiveDir
    } else {
        $parent = Split-Path -Parent $ScriptRoot
        $storageRoot = Join-Path $parent 'oscar-storage'
    }
    return (Join-Path $storageRoot 'rpm-proxy')
}

function Get-OscarVersion {
    $envFile = Join-Path $ScriptRoot '.env'
    $ver = Get-EnvFileValue $envFile 'OSCAR_VERSION'
    if ([string]::IsNullOrWhiteSpace($ver)) {
        $ver = Get-EnvFileValue (Join-Path $ScriptRoot '.env.example') 'OSCAR_VERSION'
    }
    if ([string]::IsNullOrWhiteSpace($ver)) { return 'local' }
    return $ver
}

function Ensure-ProxyImage([bool]$ForceRebuild = $false) {
    $ver = Get-OscarVersion
    $tag = "oscar-rpm-proxy:$ver"
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & docker image inspect $tag 2>&1 | Out-Null
        $exists = ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($ForceRebuild -or (-not $exists)) {
        $offlineTar = Join-Path $ScriptRoot 'offline-images.tar'
        if ((-not $exists) -and (Test-Path -LiteralPath $offlineTar)) {
            Write-Host "Importing $tag from offline-images.tar..."
            $ErrorActionPreference = 'Continue'
            try {
                & docker load --input $offlineTar | Out-Null
                & docker image inspect $tag 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { return }
            } finally {
                $ErrorActionPreference = $prevEap
            }
        }
        Write-Host "Building $tag..."
        Push-Location $ScriptRoot
        $ErrorActionPreference = 'Continue'
        try {
            & docker build --build-arg "OSCAR_VERSION=$ver" --tag $tag --file 'docker/rpm-proxy/Dockerfile' .
            if ($LASTEXITCODE -ne 0) {
                if ($exists) {
                    Write-Warning "Could not rebuild $tag (offline or registry unreachable); retaining existing local image."
                } else {
                    Fail "Failed to build $tag and no preloaded local image is available."
                }
            }
        } finally {
            $ErrorActionPreference = $prevEap
            Pop-Location
        }
    }
}

function Get-StatusEndpoint([string]$ConfigFile) {
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        return @{ Host = '127.0.0.1'; Port = '9090' }
    }
    $cfg = Get-Content -Raw -LiteralPath $ConfigFile | ConvertFrom-Json
    $st = if ($cfg.PSObject.Properties['status_listen'] -and $cfg.status_listen) { [string]$cfg.status_listen } else { '127.0.0.1:9090' }
    $lastColon = $st.LastIndexOf(':')
    if ($lastColon -le 0) { return @{ Host = '127.0.0.1'; Port = '9090' } }
    $h = $st.Substring(0, $lastColon)
    $p = $st.Substring($lastColon + 1)
    if ($h -in @('0.0.0.0', '::', '[::]')) { $h = '127.0.0.1' }
    return @{ Host = $h; Port = $p }
}

function Write-NetworkOverride([string]$ProxyDir, [string]$ConfigFile) {
    $cfg = Get-Content -Raw -LiteralPath $ConfigFile | ConvertFrom-Json
    $ports = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $enabledCount = 0
    foreach ($svc in $cfg.services) {
        $isEnabled = if ($svc.PSObject.Properties['enabled']) { [bool]$svc.enabled } else { $true }
        if (-not $isEnabled) { continue }
        $enabledCount++
        $listenList = if ($svc.listen -is [System.Array]) { $svc.listen } else { @([string]$svc.listen) }
        foreach ($ep in $listenList) {
            $epStr = [string]$ep
            $idx = $epStr.LastIndexOf(':')
            if ($idx -le 0) { continue }
            $h = $epStr.Substring(0, $idx)
            $p = $epStr.Substring($idx + 1)
            $mapping = if ($h -in @('0.0.0.0', '::')) { "$p`:$p/tcp" } else { "$h`:$p`:$p/tcp" }
            if (-not $seen.ContainsKey($mapping)) {
                $seen[$mapping] = $true
                $ports.Add($mapping)
            }
        }
    }
    if ($enabledCount -gt 12) {
        Write-Warning "Configured $enabledCount RPM lanes on Windows 11 Docker Desktop (WSL 2 NAT). For 10..50 real-time side-by-side CAS lanes, Ubuntu Server 24.04 LTS (native host networking) is strongly recommended."
    }
    $stInfo = Get-StatusEndpoint $ConfigFile
    # Always publish status endpoint on 127.0.0.1 for local health inspection; container listens on 0.0.0.0:<port> or configured IP
    $stMapping = "127.0.0.1:$($stInfo.Port):$($stInfo.Port)/tcp"
    if (-not $seen.ContainsKey($stMapping)) {
        $ports.Add($stMapping)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('services:')
    $lines.Add('  rpm-proxy:')
    $lines.Add('    ports:')
    foreach ($pm in $ports) {
        $lines.Add("      - `"$pm`"")
    }
    $overridePath = Join-Path $ProxyDir 'compose.network.yaml'
    [System.IO.File]::WriteAllLines($overridePath, $lines, $Utf8NoBom)
}

function Invoke-ProxyCompose([string[]]$ComposeArgs) {
    $rpDir = Get-RpmProxyDir
    $configFile = Join-Path $rpDir 'config.json'
    $overrideFile = Join-Path $rpDir 'compose.network.yaml'
    if (-not (Test-Path -LiteralPath $configFile)) {
        Fail "RPM Edge Proxy is not configured ($configFile not found). Run '.\oscar.bat rpm-proxy configure -FromCsv <config.csv>' first."
    }
    if (-not (Test-Path -LiteralPath $overrideFile)) {
        Write-NetworkOverride $rpDir $configFile
    }
    $stInfo = Get-StatusEndpoint $configFile
    $envFile = Join-Path $ScriptRoot '.env'
    $saved = @{}
    $keys = @(
        'OSCAR_VERSION', 'OSCAR_TIMEZONE', 'OSCAR_RPM_PROXY_CONFIG_FILE',
        'OSCAR_RPM_PROXY_STATUS_CHECK_HOST', 'OSCAR_RPM_PROXY_STATUS_PORT'
    )
    foreach ($k in $keys) {
        if (Test-Path "Env:$k") { $saved[$k] = (Get-Item "Env:$k").Value }
    }

    $env:OSCAR_VERSION = Get-OscarVersion
    $tz = Get-EnvFileValue $envFile 'OSCAR_TIMEZONE'
    $env:OSCAR_TIMEZONE = if ($tz) { $tz } else { 'UTC' }
    $env:OSCAR_RPM_PROXY_CONFIG_FILE = ($configFile -replace '\\', '/')
    $env:OSCAR_RPM_PROXY_STATUS_CHECK_HOST = $stInfo.Host
    $env:OSCAR_RPM_PROXY_STATUS_PORT = $stInfo.Port

    $dockerArgs = New-Object System.Collections.Generic.List[string]
    $dockerArgs.Add('compose')
    $dockerArgs.Add('--project-name')
    $dockerArgs.Add('oscar-rpm-proxy')
    if (Test-Path -LiteralPath $envFile) {
        $dockerArgs.Add('--env-file')
        $dockerArgs.Add($envFile)
    }
    $dockerArgs.Add('--file')
    $dockerArgs.Add((Join-Path $ScriptRoot 'compose.rpm-proxy.yaml'))
    $dockerArgs.Add('--file')
    $dockerArgs.Add($overrideFile)
    foreach ($a in $ComposeArgs) { $dockerArgs.Add($a) }

    Push-Location $ScriptRoot
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & docker $dockerArgs.ToArray()
        if ($LASTEXITCODE -ne 0) { Fail "Docker Compose rpm-proxy command failed ($LASTEXITCODE)." }
    } finally {
        $ErrorActionPreference = $prevEap
        Pop-Location
        foreach ($k in $keys) {
            if ($saved.ContainsKey($k)) { Set-Item "Env:$k" -Value $saved[$k] }
            else { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
        }
    }
}

if ($env:OSCAR_STORAGE_TEST_MODE -eq '1' -and $env:OSCAR_RPM_PROXY_TEST_ALLOW -ne '1') {
    if ($Subcommand.ToLowerInvariant() -in @('build-image-only', 'sync', 'stop-if-enabled', 'support-snapshot')) {
        exit 0
    }
}

switch ($Subcommand.ToLowerInvariant()) {
    { $_ -in @('help', '--help', '-h') } {
        Write-Host @'
OSCAR Side-by-Side CAS Rapiscan RPM Real-Time Edge Proxy (oscar-rpm-proxy)

Maintains one upstream TCP connection per Rapiscan RPM and fans out real-time
telemetry simultaneously to both an existing Central Alarm Station (CAS) and
OSCAR with <= 4.0s upstream-gated disconnect propagation.
(Note: For 10..50 real-time RPM lanes or Virtual-IP :1600 topology, Ubuntu
Server 24.04 LTS is recommended; Windows 11 supports Port-Mapped mode for
small 1..12 lane sites.)

  .\oscar.bat rpm-proxy configure -FromCsv <LANES_CSV> [-Mode port-map] [-BasePort 11601]
      [-OscarTargetHost host.docker.internal] [-ClientWrites discard|allow_primary|forward]
      [-IdleTimeoutSeconds 4.0] [-EmitOscarCsv <PATH>] [-Start]
  .\oscar.bat rpm-proxy configure -ConfigFile <CUSTOM_JSON> [-Start]
  .\oscar.bat rpm-proxy validate
  .\oscar.bat rpm-proxy start
  .\oscar.bat rpm-proxy stop
  .\oscar.bat rpm-proxy restart
  .\oscar.bat rpm-proxy upgrade
  .\oscar.bat rpm-proxy status
  .\oscar.bat rpm-proxy logs [-Tail 200] [-Follow]
  .\oscar.bat rpm-proxy disable
'@
    }
    'configure' {
        $fromCsv = ''
        $customConfig = ''
        $mode = 'port-map'
        $listenHost = '0.0.0.0'
        $basePort = '11601'
        $oscarTargetHost = 'host.docker.internal'
        $clientWrites = 'discard'
        $idleTimeout = '4.0'
        $firstLineTimeout = '4.0'
        $statusListen = '0.0.0.0:9090'
        $emitOscarCsv = ''
        $startNow = $false
        $allowedClients = New-Object System.Collections.Generic.List[string]
        $primaryWriters = New-Object System.Collections.Generic.List[string]

        $i = 0
        while ($i -lt $RemainingArgs.Count) {
            switch ($RemainingArgs[$i].ToLowerInvariant()) {
                { $_ -in @('-fromcsv', '--from-csv') } { $i++; $fromCsv = $RemainingArgs[$i] }
                { $_ -in @('-configfile', '--config-file') } { $i++; $customConfig = $RemainingArgs[$i] }
                { $_ -in @('-mode', '--mode') } { $i++; $mode = $RemainingArgs[$i] }
                { $_ -in @('-listenhost', '--listen-host') } { $i++; $listenHost = $RemainingArgs[$i] }
                { $_ -in @('-baseport', '--base-port') } { $i++; $basePort = $RemainingArgs[$i] }
                { $_ -in @('-oscartargethost', '--oscar-target-host') } { $i++; $oscarTargetHost = $RemainingArgs[$i] }
                { $_ -in @('-clientwrites', '--client-writes') } { $i++; $clientWrites = $RemainingArgs[$i] }
                { $_ -in @('-idletimeoutseconds', '--idle-timeout-seconds') } { $i++; $idleTimeout = $RemainingArgs[$i] }
                { $_ -in @('-firstlinetimeoutseconds', '--first-line-timeout-seconds') } { $i++; $firstLineTimeout = $RemainingArgs[$i] }
                { $_ -in @('-statuslisten', '--status-listen') } { $i++; $statusListen = $RemainingArgs[$i] }
                { $_ -in @('-emitoscarcsv', '--emit-oscar-csv') } { $i++; $emitOscarCsv = $RemainingArgs[$i] }
                { $_ -in @('-allowedclient', '--allowed-client') } { $i++; $allowedClients.Add($RemainingArgs[$i]) }
                { $_ -in @('-primarywriteclient', '--primary-write-client') } { $i++; $primaryWriters.Add($RemainingArgs[$i]) }
                { $_ -in @('-start', '--start') } { $startNow = $true }
                default { Fail "Unknown option for rpm-proxy configure: $($RemainingArgs[$i])" }
            }
            $i++
        }

        if ([string]::IsNullOrWhiteSpace($fromCsv) -and [string]::IsNullOrWhiteSpace($customConfig)) {
            Fail 'Specify either -FromCsv <LANES_CSV> or -ConfigFile <JSON>.'
        }
        if ((-not [string]::IsNullOrWhiteSpace($fromCsv)) -and (-not [string]::IsNullOrWhiteSpace($customConfig))) {
            Fail 'Specify either -FromCsv or -ConfigFile, not both.'
        }
        if ($mode -cne 'port-map') {
            Fail "Windows 11 Docker Desktop supports '-Mode port-map' only. Use Ubuntu Server 24.04 LTS for '-Mode virtual-ip' (:1600 per lane)."
        }

        $rpDir = Get-RpmProxyDir
        New-Item -ItemType Directory -Force -Path $rpDir | Out-Null
        $configOut = Join-Path $rpDir 'config.json'
        if ([string]::IsNullOrWhiteSpace($emitOscarCsv)) {
            $emitOscarCsv = Join-Path $rpDir 'oscar-proxied-lanes.csv'
        }

        if (-not [string]::IsNullOrWhiteSpace($customConfig)) {
            if (-not (Test-Path -LiteralPath $customConfig)) { Fail "Custom config file not found: $customConfig" }
            Copy-Item -LiteralPath $customConfig -Destination $configOut -Force
        } else {
            if (-not (Test-Path -LiteralPath $fromCsv)) { Fail "Input lane CSV file not found: $fromCsv" }
            $pythonCmd = $null
            foreach ($cand in @('python3', 'python')) {
                $cmdObj = Get-Command $cand -ErrorAction SilentlyContinue
                if ($cmdObj -and $cmdObj.Source -notmatch 'WindowsApps') { $pythonCmd = $cand; break }
            }
            if ($pythonCmd) {
                $prevPyPath = $env:PYTHONPATH
                try {
                    $env:PYTHONPATH = Join-Path $ScriptRoot 'docker\rpm-proxy'
                    $pyArgs = @(
                        '-m', 'oscar_rpm_proxy',
                        '--generate-from-csv', $fromCsv,
                        '--config', $configOut,
                        '--mode', $mode,
                        '--listen-host', $listenHost,
                        '--base-port', $basePort,
                        '--no-loopback-listener',
                        '--oscar-target-host', $oscarTargetHost,
                        '--client-writes', $clientWrites,
                        '--idle-timeout-seconds', $idleTimeout,
                        '--first-line-timeout-seconds', $firstLineTimeout,
                        '--status-listen', $statusListen,
                        '--emit-oscar-csv', $emitOscarCsv
                    )
                    foreach ($c in $allowedClients) { $pyArgs += @('--allowed-client', $c) }
                    foreach ($w in $primaryWriters) { $pyArgs += @('--primary-write-client', $w) }
                    & $pythonCmd @pyArgs
                    if ($LASTEXITCODE -ne 0) { Fail "Failed to generate RPM proxy configuration ($LASTEXITCODE)." }
                } finally {
                    $env:PYTHONPATH = $prevPyPath
                }
            } else {
                Ensure-ProxyImage $false
                $ver = Get-OscarVersion
                $csvAbs = (Resolve-Path -LiteralPath $fromCsv).Path
                $outDir = Split-Path -Parent ([IO.Path]::GetFullPath($emitOscarCsv))
                $outLeaf = Split-Path -Leaf ([IO.Path]::GetFullPath($emitOscarCsv))
                New-Item -ItemType Directory -Force -Path $outDir | Out-Null
                $dkArgs = @(
                    'run', '--rm',
                    '-v', "$($csvAbs -replace '\\','/'):/in/lanes.csv:ro",
                    '-v', "$($rpDir -replace '\\','/'):/out",
                    '-v', "$($outDir -replace '\\','/'):/oscar_csv_out",
                    "oscar-rpm-proxy:$ver",
                    '--generate-from-csv', '/in/lanes.csv',
                    '--config', '/out/config.json',
                    '--mode', $mode,
                    '--listen-host', $listenHost,
                    '--base-port', $basePort,
                    '--no-loopback-listener',
                    '--oscar-target-host', $oscarTargetHost,
                    '--client-writes', $clientWrites,
                    '--idle-timeout-seconds', $idleTimeout,
                    '--first-line-timeout-seconds', $firstLineTimeout,
                    '--status-listen', $statusListen,
                    '--emit-oscar-csv', "/oscar_csv_out/$outLeaf"
                )
                foreach ($c in $allowedClients) { $dkArgs += @('--allowed-client', $c) }
                foreach ($w in $primaryWriters) { $dkArgs += @('--primary-write-client', $w) }
                & docker @dkArgs
                if ($LASTEXITCODE -ne 0) { Fail "Failed to generate RPM proxy configuration ($LASTEXITCODE)." }
            }
            Write-Host "Generated proxy configuration: $configOut"
            Write-Host "Generated 20-column OSCAR import CSV: $emitOscarCsv"
        }

        Write-NetworkOverride $rpDir $configOut
        $stInfo = Get-StatusEndpoint $configOut
        $envPath = Join-Path $rpDir 'rpm-proxy.env'
        $existingEnabled = Get-EnvFileValue $envPath 'RPM_PROXY_ENABLED'
        $enabledVal = if ($existingEnabled) { $existingEnabled } else { 'false' }
        $envLines = @(
            "RPM_PROXY_ENABLED=$enabledVal",
            "RPM_PROXY_MODE=$mode",
            "RPM_PROXY_STATUS_HOST=$($stInfo.Host)",
            "RPM_PROXY_STATUS_PORT=$($stInfo.Port)"
        )
        [System.IO.File]::WriteAllLines($envPath, $envLines, $Utf8NoBom)

        if ($startNow) {
            & $MyInvocation.MyCommand.Path 'start'
            exit $LASTEXITCODE
        } else {
            Write-Host "Run '.\oscar.bat rpm-proxy start' to launch the side-by-side RPM fan-out proxy."
        }
    }
    'validate' {
        $rpDir = Get-RpmProxyDir
        $configFile = Join-Path $rpDir 'config.json'
        if (-not (Test-Path -LiteralPath $configFile)) { Fail "RPM Edge Proxy config not found: $configFile" }
        Ensure-ProxyImage $false
        $ver = Get-OscarVersion
        & docker run --rm -v "$($configFile -replace '\\','/'):/config/config.json:ro" "oscar-rpm-proxy:$ver" --config /config/config.json --validate
        exit $LASTEXITCODE
    }
    { $_ -in @('start', 'enable') } {
        $rpDir = Get-RpmProxyDir
        $configFile = Join-Path $rpDir 'config.json'
        if (-not (Test-Path -LiteralPath $configFile)) {
            Fail "RPM Edge Proxy is not configured ($configFile not found). Run '.\oscar.bat rpm-proxy configure -FromCsv <CSV>' first."
        }
        Write-NetworkOverride $rpDir $configFile
        Ensure-ProxyImage $false
        $envPath = Join-Path $rpDir 'rpm-proxy.env'
        $stInfo = Get-StatusEndpoint $configFile
        $mode = Get-EnvFileValue $envPath 'RPM_PROXY_MODE'
        if (-not $mode) { $mode = 'port-map' }
        [System.IO.File]::WriteAllLines($envPath, @(
            'RPM_PROXY_ENABLED=true',
            "RPM_PROXY_MODE=$mode",
            "RPM_PROXY_STATUS_HOST=$($stInfo.Host)",
            "RPM_PROXY_STATUS_PORT=$($stInfo.Port)"
        ), $Utf8NoBom)
        Invoke-ProxyCompose @('up', '-d')
        Write-Host 'OSCAR RPM Edge Proxy started (isolated project: oscar-rpm-proxy).' -ForegroundColor Green
    }
    'stop' {
        $rpDir = Get-RpmProxyDir
        if (Test-Path -LiteralPath (Join-Path $rpDir 'config.json')) {
            Invoke-ProxyCompose @('stop')
            Write-Host 'OSCAR RPM Edge Proxy stopped.'
        } else {
            Write-Host 'OSCAR RPM Edge Proxy is not configured.'
        }
    }
    'restart' {
        $rpDir = Get-RpmProxyDir
        $configFile = Join-Path $rpDir 'config.json'
        if (-not (Test-Path -LiteralPath $configFile)) { Fail 'RPM Edge Proxy is not configured.' }
        Write-NetworkOverride $rpDir $configFile
        Ensure-ProxyImage $false
        Invoke-ProxyCompose @('up', '-d', '--force-recreate')
        Write-Host 'OSCAR RPM Edge Proxy restarted.' -ForegroundColor Green
    }
    'upgrade' {
        $rpDir = Get-RpmProxyDir
        $configFile = Join-Path $rpDir 'config.json'
        if (-not (Test-Path -LiteralPath $configFile)) { Fail 'RPM Edge Proxy is not configured.' }
        Write-NetworkOverride $rpDir $configFile
        $hasOffline = Test-Path -LiteralPath (Join-Path $ScriptRoot 'offline-images.tar')
        Ensure-ProxyImage (-not $hasOffline)
        Invoke-ProxyCompose @('up', '-d', '--force-recreate')
        Write-Host "OSCAR RPM Edge Proxy upgraded to version $(Get-OscarVersion)." -ForegroundColor Green
    }
    'build-image-only' {
        $rpDir = Get-RpmProxyDir
        $enabled = Get-EnvFileValue (Join-Path $rpDir 'rpm-proxy.env') 'RPM_PROXY_ENABLED'
        if ($enabled -ceq 'true' -and (Test-Path -LiteralPath (Join-Path $rpDir 'config.json'))) {
            $hasOffline = Test-Path -LiteralPath (Join-Path $ScriptRoot 'offline-images.tar')
            Ensure-ProxyImage (-not $hasOffline)
            Write-Host "OSCAR RPM Edge Proxy kept running uninterrupted for active CAS feeds (run '.\oscar.bat rpm-proxy upgrade' during a maintenance window to switch container image)."
        }
    }
    'status' {
        $rpDir = Get-RpmProxyDir
        $configFile = Join-Path $rpDir 'config.json'
        if (-not (Test-Path -LiteralPath $configFile)) {
            Write-Host 'RPM Edge Proxy: disabled (not configured)'
            exit 0
        }
        $enabled = Get-EnvFileValue (Join-Path $rpDir 'rpm-proxy.env') 'RPM_PROXY_ENABLED'
        $mode = Get-EnvFileValue (Join-Path $rpDir 'rpm-proxy.env') 'RPM_PROXY_MODE'
        if (-not $enabled) { $enabled = 'false' }
        if (-not $mode) { $mode = 'custom' }
        Write-Host "RPM Edge Proxy: enabled=$enabled mode=$mode config=$configFile"
        if (Get-Command docker -ErrorAction SilentlyContinue) {
            try { Invoke-ProxyCompose @('ps') } catch {}
        }
        $stInfo = Get-StatusEndpoint $configFile
        try {
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$($stInfo.Port)/status" -TimeoutSec 2 -ErrorAction Stop
            Write-Host "Live Telemetry: status=$($resp.status) connected_lanes=$($resp.connected_lanes)/$($resp.configured_lanes) uptime=$($resp.uptime_seconds)s"
        } catch {}
    }
    'logs' {
        $tail = '200'
        $follow = $false
        $i = 0
        while ($i -lt $RemainingArgs.Count) {
            switch ($RemainingArgs[$i].ToLowerInvariant()) {
                { $_ -in @('-tail', '--tail') } { $i++; $tail = $RemainingArgs[$i] }
                { $_ -in @('-follow', '--follow', '-f') } { $follow = $true }
                default { Fail "Unknown option for rpm-proxy logs: $($RemainingArgs[$i])" }
            }
            $i++
        }
        $cArgs = @('logs', '--tail', $tail)
        if ($follow) { $cArgs += '--follow' }
        Invoke-ProxyCompose $cArgs
    }
    'support-snapshot' {
        if ($RemainingArgs.Count -lt 1) { exit 0 }
        $destDir = $RemainingArgs[0]
        $rpDir = Get-RpmProxyDir
        $configFile = Join-Path $rpDir 'config.json'
        if (-not (Test-Path -LiteralPath $configFile)) { exit 0 }
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        Copy-Item -LiteralPath $configFile -Destination (Join-Path $destDir 'config.json') -Force -ErrorAction SilentlyContinue
        $envPath = Join-Path $rpDir 'rpm-proxy.env'
        if (Test-Path -LiteralPath $envPath) { Copy-Item -LiteralPath $envPath -Destination (Join-Path $destDir 'rpm-proxy.env') -Force -ErrorAction SilentlyContinue }
        $stInfo = Get-StatusEndpoint $configFile
        try {
            $stRaw = Invoke-WebRequest -Uri "http://127.0.0.1:$($stInfo.Port)/status" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            [System.IO.File]::WriteAllText((Join-Path $destDir 'status.json'), $stRaw.Content, $Utf8NoBom)
        } catch {}
    }
    'disable' {
        $rpDir = Get-RpmProxyDir
        if (Test-Path -LiteralPath (Join-Path $rpDir 'config.json')) {
            try { Invoke-ProxyCompose @('down', '--remove-orphans') } catch {}
        }
        $envPath = Join-Path $rpDir 'rpm-proxy.env'
        if (Test-Path -LiteralPath $envPath) {
            $content = [System.IO.File]::ReadAllText($envPath) -replace 'RPM_PROXY_ENABLED=true', 'RPM_PROXY_ENABLED=false'
            [System.IO.File]::WriteAllText($envPath, $content, $Utf8NoBom)
        }
        Write-Host 'OSCAR RPM Edge Proxy disabled.'
    }
    default {
        Fail "Unknown rpm-proxy subcommand: $Subcommand (run '.\oscar.bat rpm-proxy help' for usage)."
    }
}
