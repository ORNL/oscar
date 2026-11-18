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

function Get-RemoteAccessDir {
    $envFile = Join-Path $ScriptRoot '.env'
    $archiveDir = Get-EnvFileValue $envFile 'OSCAR_ARCHIVE_DIR'
    if (-not [string]::IsNullOrWhiteSpace($archiveDir)) {
        $storageRoot = Split-Path -Parent $archiveDir
    } else {
        $parent = Split-Path -Parent $ScriptRoot
        $storageRoot = Join-Path $parent 'oscar-storage'
    }
    return (Join-Path $storageRoot 'remote-access')
}

function Ensure-TunnelImage([string]$OscarVersion, [bool]$ForceRebuild = $false) {
    $ver = if ([string]::IsNullOrWhiteSpace($OscarVersion)) { 'local' } else { $OscarVersion }
    $tag = "oscar-tunnel:$ver"
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & docker image inspect $tag 2>&1 | Out-Null
        $exists = ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $prevEap
    }
    if ($ForceRebuild -or (-not $exists)) {
        Write-Host "Building $tag..."
        Push-Location $ScriptRoot
        $ErrorActionPreference = 'Continue'
        try {
            & docker build --build-arg "OSCAR_VERSION=$ver" --tag $tag --file 'docker/tunnel/Dockerfile' .
            if ($LASTEXITCODE -ne 0) {
                if ($exists) {
                    Write-Warning "Could not rebuild $tag (offline or registry unreachable); retaining existing local tunnel image."
                } else {
                    Fail "Failed to build $tag."
                }
            }
        } finally {
            $ErrorActionPreference = $prevEap
            Pop-Location
        }
    }
}

function Invoke-TunnelCompose([string[]]$ComposeArgs) {
    $raDir = Get-RemoteAccessDir
    $cfgFile = Join-Path $raDir 'octelium.env'
    if (-not (Test-Path -LiteralPath $cfgFile)) {
        Fail "Remote access is not configured ($cfgFile not found)."
    }
    $envFile = Join-Path $ScriptRoot '.env'
    $saved = @{}
    $keys = @(
        'OSCAR_VERSION', 'OSCAR_TIMEZONE', 'OCTELIUM_DOMAIN', 'OCTELIUM_SERVICE',
        'OCTELIUM_TOKEN_FILE', 'OCTELIUM_INSECURE_TLS', 'OCTELIUM_TUNNEL_MODE',
        'OCTELIUM_IMPLEMENTATION', 'OCTELIUM_IP_MODE', 'OCTELIUM_SCOPE'
    )
    foreach ($k in $keys) {
        if (Test-Path "Env:$k") { $saved[$k] = (Get-Item "Env:$k").Value }
    }

    $ver = Get-EnvFileValue $envFile 'OSCAR_VERSION'
    $tz  = Get-EnvFileValue $envFile 'OSCAR_TIMEZONE'
    $env:OSCAR_VERSION = if ($ver) { $ver } else { 'local' }
    $env:OSCAR_TIMEZONE = if ($tz) { $tz } else { 'UTC' }
    $env:OCTELIUM_DOMAIN = Get-EnvFileValue $cfgFile 'OCTELIUM_DOMAIN'
    $env:OCTELIUM_SERVICE = Get-EnvFileValue $cfgFile 'OCTELIUM_SERVICE'
    $env:OCTELIUM_TOKEN_FILE = (Get-EnvFileValue $cfgFile 'OCTELIUM_TOKEN_FILE') -replace '\\', '/'
    $insecure = Get-EnvFileValue $cfgFile 'OCTELIUM_INSECURE_TLS'
    $tmode = Get-EnvFileValue $cfgFile 'OCTELIUM_TUNNEL_MODE'
    $impl = Get-EnvFileValue $cfgFile 'OCTELIUM_IMPLEMENTATION'
    $ipm = Get-EnvFileValue $cfgFile 'OCTELIUM_IP_MODE'
    $env:OCTELIUM_INSECURE_TLS = if ($insecure) { $insecure } else { 'false' }
    $env:OCTELIUM_TUNNEL_MODE = if ($tmode) { $tmode } else { 'wg' }
    $env:OCTELIUM_IMPLEMENTATION = if ($impl) { $impl } else { 'gvisor' }
    $env:OCTELIUM_IP_MODE = if ($ipm) { $ipm } else { 'v4' }
    $env:OCTELIUM_SCOPE = Get-EnvFileValue $cfgFile 'OCTELIUM_SCOPE'

    Push-Location $ScriptRoot
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & docker (@(
            'compose', '--project-name', 'oscar',
            '--env-file', (Join-Path $ScriptRoot '.env'),
            '--file', (Join-Path $ScriptRoot 'compose.yaml'),
            '--file', (Join-Path $ScriptRoot 'compose.octelium.yaml')
        ) + $ComposeArgs)
        if ($LASTEXITCODE -ne 0) { Fail "Docker Compose tunnel command failed ($LASTEXITCODE)." }
    } finally {
        $ErrorActionPreference = $prevEap
        Pop-Location
        foreach ($k in $keys) {
            if ($saved.ContainsKey($k)) { Set-Item "Env:$k" -Value $saved[$k] }
            else { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
        }
    }
}

if ($env:OSCAR_STORAGE_TEST_MODE -eq '1' -and $env:OSCAR_REMOTE_ACCESS_TEST_ALLOW -ne '1') {
    if ($Subcommand.ToLowerInvariant() -in @('enable', 'rotate-token', 'disable', 'sync', 'stop-if-enabled')) {
        exit 0
    }
}

switch ($Subcommand.ToLowerInvariant()) {
    { $_ -in @('help', '--help', '-h') } {
        Write-Host @'
OSCAR Remote Access Administration (Octelium Zero Trust Sidecar)

  .\oscar.bat remote-access enable -Domain <CLUSTER_DOMAIN> -Service <SERVICE_NAME> -TokenFile <PATH> [-InsecureTls] [-TunnelMode wg|quicv0]
  .\oscar.bat remote-access status
  .\oscar.bat remote-access logs [-Tail 200] [-Follow]
  .\oscar.bat remote-access rotate-token -TokenFile <PATH>
  .\oscar.bat remote-access disable [-PurgeToken]
'@
    }
    'enable' {
        $domain = ''; $service = ''; $tokenFile = ''; $insecureTls = 'false'; $tunnelMode = 'wg'; $scope = ''
        for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
            switch -Regex ($RemainingArgs[$i]) {
                '^-{1,2}domain$'      { $i++; $domain = $RemainingArgs[$i] }
                '^-{1,2}service$'     { $i++; $service = $RemainingArgs[$i] }
                '^-{1,2}token-?file$' { $i++; $tokenFile = $RemainingArgs[$i] }
                '^-{1,2}insecure-?tls$' { $insecureTls = 'true' }
                '^-{1,2}tunnel-?mode$' { $i++; $tunnelMode = $RemainingArgs[$i] }
                '^-{1,2}scope$'       { $i++; $scope = $RemainingArgs[$i] }
                default               { Fail "Unknown option for remote-access enable: $($RemainingArgs[$i])" }
            }
        }
        if ([string]::IsNullOrWhiteSpace($domain))    { Fail '-Domain is required.' }
        if ([string]::IsNullOrWhiteSpace($service))   { Fail '-Service is required.' }
        if ([string]::IsNullOrWhiteSpace($tokenFile)) { Fail '-TokenFile is required.' }
        if ($domain -notmatch '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$') { Fail "Invalid domain: $domain" }
        if ($service -notmatch '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$') { Fail "Invalid service slug: $service" }
        if (-not (Test-Path -LiteralPath $tokenFile)) { Fail "Token file not found: $tokenFile" }

        $rawToken = ([System.IO.File]::ReadAllText($tokenFile) -replace '[\r\n\s]', '')
        if ([string]::IsNullOrWhiteSpace($rawToken)) { Fail 'Token file is empty.' }

        $raDir = Get-RemoteAccessDir
        New-Item -ItemType Directory -Force -Path $raDir | Out-Null
        $tokenDest = Join-Path $raDir 'octelium-token.txt'
        $cfgDest   = Join-Path $raDir 'octelium.env'

        [System.IO.File]::WriteAllText($tokenDest, $rawToken, [System.Text.UTF8Encoding]::new($false))
        $cfgLines = @(
            "OCTELIUM_ENABLED=true",
            "OCTELIUM_DOMAIN=$domain",
            "OCTELIUM_SERVICE=$service",
            "OCTELIUM_TOKEN_FILE=$($tokenDest -replace '\\', '/')",
            "OCTELIUM_INSECURE_TLS=$insecureTls",
            "OCTELIUM_TUNNEL_MODE=$tunnelMode",
            "OCTELIUM_IMPLEMENTATION=gvisor",
            "OCTELIUM_IP_MODE=v4",
            "OCTELIUM_SCOPE=$scope"
        )
        [System.IO.File]::WriteAllLines($cfgDest, $cfgLines, [System.Text.UTF8Encoding]::new($false))

        $ver = Get-EnvFileValue (Join-Path $ScriptRoot '.env') 'OSCAR_VERSION'
        Ensure-TunnelImage $ver
        Invoke-TunnelCompose @('up', '--detach', '--no-build', 'tunnel')
        Write-Host "OSCAR Octelium tunnel enabled: https://$service.$domain"
    }
    'rotate-token' {
        $tokenFile = ''
        for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
            if ($RemainingArgs[$i] -match '^-{1,2}token-?file$') { $i++; $tokenFile = $RemainingArgs[$i] }
            else { Fail "Unknown option: $($RemainingArgs[$i])" }
        }
        if ([string]::IsNullOrWhiteSpace($tokenFile) -or -not (Test-Path -LiteralPath $tokenFile)) {
            Fail '-TokenFile must point to an existing file.'
        }
        $raDir = Get-RemoteAccessDir
        $cfgFile = Join-Path $raDir 'octelium.env'
        if (-not (Test-Path -LiteralPath $cfgFile)) { Fail 'Remote access is not configured yet.' }
        $rawToken = ([System.IO.File]::ReadAllText($tokenFile) -replace '[\r\n\s]', '')
        [System.IO.File]::WriteAllText((Join-Path $raDir 'octelium-token.txt'), $rawToken, [System.Text.UTF8Encoding]::new($false))
        if ((Get-EnvFileValue $cfgFile 'OCTELIUM_ENABLED') -eq 'true') {
            Invoke-TunnelCompose @('up', '--detach', '--force-recreate', '--no-build', 'tunnel')
        }
        Write-Host 'Rotated Octelium authentication token and restarted tunnel.'
    }
    'disable' {
        $purge = $false
        foreach ($arg in $RemainingArgs) {
            if ($arg -match '^-{1,2}purge-?token$') { $purge = $true }
        }
        $raDir = Get-RemoteAccessDir
        $cfgFile = Join-Path $raDir 'octelium.env'
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $existingId = (& docker ps -a -q --filter 'name=^/oscar-tunnel-1$' 2>$null)
            if ($existingId) { & docker rm -f oscar-tunnel-1 *> $null }
            $global:LASTEXITCODE = 0
        } finally {
            $ErrorActionPreference = $prevEap
        }
        if (Test-Path -LiteralPath $cfgFile) {
            $lines = [System.IO.File]::ReadAllLines($cfgFile) | ForEach-Object {
                if ($_ -match '^OCTELIUM_ENABLED=') { 'OCTELIUM_ENABLED=false' } else { $_ }
            }
            [System.IO.File]::WriteAllLines($cfgFile, $lines, [System.Text.UTF8Encoding]::new($false))
            if ($purge) { Remove-Item -LiteralPath (Join-Path $raDir 'octelium-token.txt') -Force -ErrorAction SilentlyContinue }
        }
        Write-Host 'OSCAR Octelium remote-access tunnel disabled.'
    }
    'status' {
        $raDir = Get-RemoteAccessDir
        $cfgFile = Join-Path $raDir 'octelium.env'
        if (-not (Test-Path -LiteralPath $cfgFile)) {
            Write-Host 'Remote Access (Octelium): disabled (not configured)'
            exit 0
        }
        $enabled = Get-EnvFileValue $cfgFile 'OCTELIUM_ENABLED'
        $domain  = Get-EnvFileValue $cfgFile 'OCTELIUM_DOMAIN'
        $service = Get-EnvFileValue $cfgFile 'OCTELIUM_SERVICE'
        Write-Host "Remote Access (Octelium): $enabled"
        Write-Host "Public Service URL:       https://$service.$domain"
        & docker ps --filter 'name=^/oscar-tunnel-1$' --format 'Tunnel Container:         {{.Names}} ({{.Status}})'
    }
    'logs' {
        $tail = '200'; $follow = $false
        for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
            switch -Regex ($RemainingArgs[$i]) {
                '^-{1,2}tail$'   { $i++; $tail = $RemainingArgs[$i] }
                '^-{1,2}(follow|f)$' { $follow = $true }
            }
        }
        $cargs = @('logs', '--tail', $tail)
        if ($follow) { $cargs += '--follow' }
        $cargs += 'tunnel'
        Invoke-TunnelCompose $cargs
    }
    'sync' {
        $rebuild = $false
        foreach ($arg in $RemainingArgs) {
            if ($arg -match '^-{1,2}rebuild$') { $rebuild = $true }
        }
        $raDir = Get-RemoteAccessDir
        $cfgFile = Join-Path $raDir 'octelium.env'
        if ((Test-Path -LiteralPath $cfgFile) -and (Get-EnvFileValue $cfgFile 'OCTELIUM_ENABLED') -eq 'true') {
            $ver = Get-EnvFileValue (Join-Path $ScriptRoot '.env') 'OSCAR_VERSION'
            Ensure-TunnelImage $ver $rebuild
            Invoke-TunnelCompose @('up', '--detach', '--force-recreate', '--no-build', 'tunnel')
        }
    }
    'stop-if-enabled' {
        $raDir = Get-RemoteAccessDir
        $cfgFile = Join-Path $raDir 'octelium.env'
        if (-not (Test-Path -LiteralPath $cfgFile)) {
            exit 0
        }
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $runningId = (& docker ps -q --filter 'name=^/oscar-tunnel-1$' 2>$null)
            if ($runningId) { & docker stop oscar-tunnel-1 *> $null }
            $global:LASTEXITCODE = 0
        } finally {
            $ErrorActionPreference = $prevEap
        }
    }
    default {
        Fail "Unknown remote-access subcommand: $Subcommand"
    }
}
