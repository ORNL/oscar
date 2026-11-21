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
$EngineScript = Join-Path $ScriptRoot 'oscar-usb-backup-engine.sh'
$TarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ConfigPath = if ($env:OSCAR_USB_BACKUP_CONFIG) {
    $env:OSCAR_USB_BACKUP_CONFIG
} else {
    Join-Path $env:ProgramData 'OSCAR\usb-backup.json'
}
$TaskName = 'OSCAR-ContinualBackup'

function Fail([string]$Message) {
    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

function Write-Heading([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Assert-Administrator {
    if ($env:OSCAR_USB_BACKUP_ALLOW_NONADMIN -eq '1') { return }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Fail 'Run this command from an Administrator Windows PowerShell 5.1 window (or via .\oscar.bat).'
    }
}

function Get-FileSha256Lower([string]$FilePath) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $FilePath).Hash.ToLowerInvariant()
}

function Get-HmacBase64([byte[]]$DataBytes, [string]$KeyFilePath) {
    $keyStr = ([System.IO.File]::ReadAllText($KeyFilePath)).TrimEnd("`r", "`n")
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,[System.Text.Encoding]::UTF8.GetBytes($keyStr))
    try {
        return [Convert]::ToBase64String($hmac.ComputeHash($DataBytes))
    } finally {
        $hmac.Dispose()
    }
}

function Get-EnvFileValue([string]$FilePath, [string]$Key, [string]$DefaultValue = '') {
    if (-not (Test-Path -LiteralPath $FilePath)) { return $DefaultValue }
    foreach ($line in [System.IO.File]::ReadAllLines($FilePath)) {
        $trimmed = $line.TrimEnd("`r")
        $idx = $trimmed.IndexOf('=')
        if ($idx -gt 0 -and $trimmed.Substring(0, $idx) -ceq $Key) {
            $val = $trimmed.Substring($idx + 1)
            if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
        }
    }
    return $DefaultValue
}

function Get-OscarVersion {
    $envFile = Join-Path $ScriptRoot '.env'
    $v = Get-EnvFileValue $envFile 'OSCAR_VERSION' ''
    if ([string]::IsNullOrWhiteSpace($v)) {
        $v = Get-EnvFileValue (Join-Path $ScriptRoot '.env.example') 'OSCAR_VERSION' 'local'
    }
    return $v
}

function Resolve-ArchiveDirectory([string]$Override = '') {
    $raw = if (-not [string]::IsNullOrWhiteSpace($Override)) {
        $Override
    } else {
        Get-EnvFileValue (Join-Path $ScriptRoot '.env') 'OSCAR_ARCHIVE_DIR' '..\oscar-storage\archive'
    }
    if ([System.IO.Path]::IsPathRooted($raw)) {
        return [System.IO.Path]::GetFullPath($raw)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot $raw))
}

function Read-UsbConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    return (Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json)
}

function Save-UsbConfig([string]$TargetPath, [string]$Mode, [int]$IntervalMinutes, [string]$DriveLetter, [int]$DiskNumber) {
    $dir = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $obj = [ordered]@{
        targetPath      = $TargetPath
        mode            = $Mode
        intervalMinutes = $IntervalMinutes
        driveLetter     = $DriveLetter
        diskNumber      = $DiskNumber
        releaseRoot     = $ScriptRoot
        updatedAt       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    $json = $obj | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($ConfigPath, $json, $Utf8NoBom)
}

function Ensure-BackupKey([string]$CustomPath = '') {
    $keyPath = if (-not [string]::IsNullOrWhiteSpace($CustomPath)) {
        $CustomPath
    } else {
        Join-Path $ScriptRoot 'secrets\backup-key.txt'
    }
    if (-not (Test-Path -LiteralPath $keyPath)) {
        $secDir = Split-Path -Parent $keyPath
        if (-not (Test-Path -LiteralPath $secDir)) {
            New-Item -ItemType Directory -Path $secDir -Force | Out-Null
        }
        $bytes = New-Object byte[] 48
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($bytes)
        $rng.Dispose()
        $secret = [Convert]::ToBase64String($bytes) + "`n"
        [System.IO.File]::WriteAllText($keyPath, $secret, $Utf8NoBom)
        Write-Host "Generated new AES-256/HMAC backup key at $keyPath" -ForegroundColor Yellow
        Write-Host "IMPORTANT: Copy $keyPath to secure off-host escrow (never store it solely on the USB backup drive)." -ForegroundColor Yellow
    }
    return [System.IO.Path]::GetFullPath($keyPath)
}

function Acquire-StorageLock {
    $depId = Get-EnvFileValue (Join-Path $ScriptRoot '.env') 'OSCAR_DEPLOYMENT_ID' 'uninitialized'
    $lockDir = Join-Path $env:ProgramData 'OSCAR\StorageLocks'
    if (-not (Test-Path -LiteralPath $lockDir)) {
        New-Item -ItemType Directory -Path $lockDir -Force | Out-Null
    }
    $lockPath = Join-Path $lockDir "oscar-storage-$depId.lock"
    $deadline = (Get-Date).AddSeconds(120)
    while ($true) {
        try {
            return [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch {
            if ((Get-Date) -ge $deadline) {
                Fail "Another OSCAR storage or backup operation is holding lock $lockPath."
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Invoke-Compose([string[]]$ComposeArgs) {
    $envFile = Join-Path $ScriptRoot '.env'
    $composeFile = Join-Path $ScriptRoot 'compose.yaml'
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & docker compose --project-name oscar --project-directory $ScriptRoot --env-file $envFile --file $composeFile @ComposeArgs
        if ($LASTEXITCODE -ne 0) {
            Fail "docker compose $($ComposeArgs -join ' ') failed with exit code $LASTEXITCODE."
        }
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Test-DriveAttached($Cfg) {
    if ($null -eq $Cfg) { return $false }
    $p = [string]$Cfg.targetPath
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    if (-not (Test-Path -LiteralPath $p)) { return $false }
    if (Test-Path -LiteralPath (Join-Path $p '.oscar-ejected')) { return $false }
    $marker = Join-Path $p 'OSCAR-Backup\.oscar-usb-backup-root'
    return (Test-Path -LiteralPath $marker)
}

function Configure-ScheduledTask([string]$Mode, [int]$IntervalMinutes) {
    if ($env:OSCAR_USB_BACKUP_SKIP_TASK -eq '1') { return }
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    if ($Mode -ceq 'continual') {
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $scriptFull = Join-Path $ScriptRoot 'oscar-usb-backup.ps1'
        $argStr = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$scriptFull`" sync -IfAttached"
        $action = New-ScheduledTaskAction -Execute $psExe -Argument $argStr -WorkingDirectory $ScriptRoot
        $triggerBoot = New-ScheduledTaskTrigger -AtStartup
        $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
            -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4) -Priority 8
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($triggerBoot, $triggerRepeat) `
            -Settings $settings -Principal $principal -Force | Out-Null
    }
}

function Invoke-ListDrives {
    Write-Heading 'Candidate External USB / Secondary Volumes (Windows)'
    $sysDrive = ($env:SystemDrive -replace ':','').ToUpperInvariant()
    Get-Disk | Select-Object Number, FriendlyName, BusType, OperationalStatus, IsSystem, IsBoot, @{
        Name = 'SizeGB'; Expression = { [Math]::Round($_.Size / 1GB, 1) }
    } | Format-Table -AutoSize
    Get-Volume | Where-Object { $_.DriveLetter } | Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, @{
        Name = 'SizeGB'; Expression = { [Math]::Round($_.Size / 1GB, 1) }
    }, @{
        Name = 'FreeGB'; Expression = { [Math]::Round($_.SizeRemaining / 1GB, 1) }
    }, @{
        Name = 'Protected'; Expression = { $_.DriveLetter -eq $sysDrive }
    } | Format-Table -AutoSize
}

function Invoke-PrepareDrive([string[]]$Tokens) {
    Assert-Administrator
    $envFile = Join-Path $ScriptRoot '.env'
    if (-not (Test-Path -LiteralPath $envFile)) {
        Fail 'Initialize OSCAR first (.\oscar.bat init) before preparing a USB backup drive.'
    }
    $driveLetter = ''
    $pathOnly = ''
    $doFormat = $false
    $mode = 'continual'
    $interval = 15
    $confirm = ''
    $skipSync = $false

    $i = 0
    while ($i -lt $Tokens.Count) {
        switch -Regex ($Tokens[$i]) {
            '^(-DriveLetter|--drive-letter)$' { $driveLetter = $Tokens[$i + 1]; $i += 2; continue }
            '^(-Path|--path)$'                { $pathOnly = $Tokens[$i + 1]; $i += 2; continue }
            '^(-Format|--format)$'            { $doFormat = $true; $i += 1; continue }
            '^(-Mode|--mode)$'                { $mode = $Tokens[$i + 1].ToLowerInvariant(); $i += 2; continue }
            '^(-IntervalMinutes|--interval-minutes)$' { $interval = [int]$Tokens[$i + 1]; $i += 2; continue }
            '^(-Confirm|--confirm)$'          { $confirm = $Tokens[$i + 1]; $i += 2; continue }
            '^(-SkipInitialSync|--skip-initial-sync)$' { $skipSync = $true; $i += 1; continue }
            default { Fail "Unknown prepare-drive option: $($Tokens[$i])" }
        }
    }

    if ($mode -cnotin @('continual', 'occasional')) { Fail '-Mode must be continual or occasional.' }
    if ($interval -lt 5 -or $interval -gt 1440) { Fail '-IntervalMinutes must be between 5 and 1440.' }

    $diskNum = -1
    $targetRoot = ''
    if (-not [string]::IsNullOrWhiteSpace($driveLetter)) {
        $dl = ($driveLetter -replace ':','').Trim().ToUpperInvariant()
        $sysDl = ($env:SystemDrive -replace ':','').ToUpperInvariant()
        if ($dl -eq $sysDl) { Fail "Refusing to use protected Windows system drive ${dl}: as a removable USB backup drive." }
        $part = Get-Partition -DriveLetter $dl -ErrorAction SilentlyContinue
        if ($null -eq $part) { Fail "Drive ${dl}: was not found." }
        $disk = Get-Disk -Number $part.DiskNumber
        if ($disk.IsBoot -or $disk.IsSystem) { Fail "Refusing to target OS boot/system disk $($disk.Number)." }
        $diskNum = [int]$disk.Number
        if ($doFormat) {
            if ($confirm -cne 'FORMAT') {
                Fail "Formatting ${dl}: erases all data on that USB drive. Re-run with -Format -Confirm FORMAT"
            }
            Write-Heading "Formatting ${dl}: as NTFS (label: OSCAR_BACKUP)"
            Format-Volume -DriveLetter $dl -FileSystem NTFS -NewFileSystemLabel 'OSCAR_BACKUP' -Confirm:$false | Out-Null
        } else {
            $vol = Get-Volume -DriveLetter $dl
            if ($vol.FileSystem -ne 'NTFS') {
                Fail "Drive ${dl}: is formatted as $($vol.FileSystem). Format it as NTFS (-Format -Confirm FORMAT) so permissions and large archives are supported."
            }
        }
        $targetRoot = "${dl}:\"
    } elseif (-not [string]::IsNullOrWhiteSpace($pathOnly)) {
        if (-not (Test-Path -LiteralPath $pathOnly)) {
            New-Item -ItemType Directory -Path $pathOnly -Force | Out-Null
        }
        $targetRoot = [System.IO.Path]::GetFullPath($pathOnly)
    } else {
        Fail 'Specify either -DriveLetter R [-Format -Confirm FORMAT] or -Path D:\OSCAR-USB-Backup.'
    }

    $archiveReal = Resolve-ArchiveDirectory
    if ($targetRoot.StartsWith($ScriptRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $targetRoot.StartsWith($archiveReal, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "USB backup target ($targetRoot) must not overlap the release directory or live archive directory."
    }

    $ejectedMarker = Join-Path $targetRoot '.oscar-ejected'
    if (Test-Path -LiteralPath $ejectedMarker) { Remove-Item -LiteralPath $ejectedMarker -Force }

    foreach ($sub in @('OSCAR-Backup\packs\archive', 'OSCAR-Backup\packs\state', 'OSCAR-Backup\snapshots')) {
        $full = Join-Path $targetRoot $sub
        if (-not (Test-Path -LiteralPath $full)) {
            New-Item -ItemType Directory -Path $full -Force | Out-Null
        }
    }

    $depId = Get-EnvFileValue $envFile 'OSCAR_DEPLOYMENT_ID' ''
    $hostName = Get-EnvFileValue $envFile 'OSCAR_HOSTNAME' 'oscar.local'
    $nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $rootMarker = "format=oscar-usb-backup-root`nversion=1`ndeployment_id=$depId`nhostname=$hostName`ncreated_at=$nowIso`n"
    [System.IO.File]::WriteAllText((Join-Path $targetRoot 'OSCAR-Backup\.oscar-usb-backup-root'), $rootMarker, $Utf8NoBom)

    Ensure-BackupKey | Out-Null
    $ver = Get-OscarVersion
    & cmd.exe /c "`"$TarExe`" -C `"$ScriptRoot`" -cf - oscar-usb-backup-engine.sh | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --read-only --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m --user 0:0 --entrypoint sh oscar:$ver -eu -c `"mkdir -p /tmp/in /tmp/h && tar -C /tmp/in -xf - && bash /tmp/in/oscar-usb-backup-engine.sh write-helpers /tmp/h && tar -C /tmp/h -cf - .`" | `"$TarExe`" -C `"$targetRoot`" -xf -"
    if ($LASTEXITCODE -ne 0) { Fail 'Failed writing laptop helper scripts onto USB backup drive.' }

    Save-UsbConfig $targetRoot $mode $interval $driveLetter $diskNum
    Configure-ScheduledTask $mode $interval
    Write-Host "Prepared OSCAR USB backup carrier at $targetRoot (mode=$mode)." -ForegroundColor Green
    if (-not $skipSync) {
        Invoke-Sync @()
    } else {
        Write-AgentStatusJson $null
    }
}

function Invoke-Mode([string[]]$Tokens) {
    Assert-Administrator
    $cfg = Read-UsbConfig
    if ($null -eq $cfg) { Fail 'No USB backup drive is configured yet. Run .\oscar.bat usb-backup prepare-drive ... first.' }
    if ($Tokens.Count -lt 1) { Fail 'Usage: .\oscar.bat usb-backup mode <continual|occasional|disabled> [-IntervalMinutes 15]' }
    $newMode = $Tokens[0].ToLowerInvariant()
    if ($newMode -cnotin @('continual', 'occasional', 'disabled')) {
        Fail 'Mode must be continual, occasional, or disabled.'
    }
    $interval = [int]$cfg.intervalMinutes
    $i = 1
    while ($i -lt $Tokens.Count) {
        if ($Tokens[$i] -match '^(-IntervalMinutes|--interval-minutes)$') {
            $interval = [int]$Tokens[$i + 1]
            $i += 2
            continue
        }
        Fail "Unknown mode option: $($Tokens[$i])"
    }
    if ($interval -lt 5 -or $interval -gt 1440) { Fail '-IntervalMinutes must be between 5 and 1440.' }

    Save-UsbConfig ([string]$cfg.targetPath) $newMode $interval ([string]$cfg.driveLetter) ([int]$cfg.diskNumber)
    Configure-ScheduledTask $newMode $interval

    switch ($newMode) {
        'continual' {
            Write-Host "Switched backup mode -> CONTINUAL (every $interval minutes, zero portal downtime)." -ForegroundColor Green
            $updatedCfg = Read-UsbConfig
            if (Test-DriveAttached $updatedCfg) {
                Invoke-Sync @()
            } else {
                Write-AgentStatusJson $null
                Write-Host "Note: USB backup drive ($($cfg.targetPath)) is currently unplugged; sync will run automatically once plugged back in."
            }
        }
        'occasional' {
            Write-AgentStatusJson $null
            Write-Host 'Switched backup mode -> OCCASIONAL (scheduled task disabled; run .\oscar.bat usb-backup sync whenever connected).' -ForegroundColor Green
        }
        'disabled' {
            Write-AgentStatusJson $null
            Write-Host 'Switched backup mode -> DISABLED (scheduled task disabled; existing USB backup files were preserved).' -ForegroundColor Green
        }
    }
}

function Invoke-Sync([string[]]$Tokens) {
    Assert-Administrator
    $cfg = Read-UsbConfig
    if ($null -eq $cfg) { Fail 'No USB backup drive is configured yet. Run .\oscar.bat usb-backup prepare-drive ... first.' }
    $quiesce = $false
    $ifAttached = $false
    foreach ($t in $Tokens) {
        switch -Regex ($t) {
            '^(-Quiesce|--quiesce)$'        { $quiesce = $true; continue }
            '^(-IfAttached|--if-attached)$' { $ifAttached = $true; continue }
            default { Fail "Unknown sync option: $t" }
        }
    }

    if (-not (Test-DriveAttached $cfg)) {
        if ($ifAttached) {
            Write-Host "USB backup drive ($($cfg.targetPath)) is currently DETACHED; OSCAR continues recording normally and will catch up when reconnected."
            return
        }
        Fail "USB backup drive is not attached at $($cfg.targetPath). Plug in the drive (or run .\oscar.bat usb-backup attach)."
    }

    $lockStream = Acquire-StorageLock
    $pgStageVol = $null
    $stateStageVol = $null
    $winStageIn = $null
    $winStageOut = $null
    try {
        $envFile = Join-Path $ScriptRoot '.env'
        $depId = Get-EnvFileValue $envFile 'OSCAR_DEPLOYMENT_ID' ''
        $rootMarkerPath = Join-Path ([string]$cfg.targetPath) 'OSCAR-Backup\.oscar-usb-backup-root'
        $rootDepId = Get-EnvFileValue $rootMarkerPath 'deployment_id' ''
        if ($depId -cne $rootDepId) {
            Fail "USB backup drive belongs to deployment $rootDepId, not active deployment $depId."
        }

        $ver = Get-OscarVersion
        $img = "oscar:$ver"
        $pgImg = "oscar-postgis:$ver"
        $archiveReal = Resolve-ArchiveDirectory
        $keyPath = Ensure-BackupKey

        $utcNow = (Get-Date).ToUniversalTime()
        $ts = $utcNow.ToString('yyyyMMddTHHmmssZ')
        $tsIso = $utcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $todayUtc = $utcNow.ToString('yyyy-MM-dd')
        $yesterdayUtc = $utcNow.AddDays(-1).ToString('yyyy-MM-dd')
        $randBytes = New-Object byte[] 4
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($randBytes); $rng.Dispose()
        $randHex = ($randBytes | ForEach-Object { $_.ToString('x2') }) -join ''
        $snapId = "$ts-$randHex"

        $targetRoot = [string]$cfg.targetPath
        $backupRoot = Join-Path $targetRoot 'OSCAR-Backup'
        $archivePacksDir = Join-Path $backupRoot 'packs\archive'
        $statePacksDir = Join-Path $backupRoot 'packs\state'
        $snapshotsDir = Join-Path $backupRoot 'snapshots'
        $workDir = Join-Path $snapshotsDir "$snapId.partial"
        if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null

        if ($quiesce) {
            Invoke-Compose @('stop', 'gateway', 'oscar')
        }

        try {
            Write-Heading "Syncing incremental backup snapshot $snapId (quiesce=$quiesce)"
            $pgCid = ([string](& docker compose --project-name oscar --project-directory $ScriptRoot --env-file $envFile --file (Join-Path $ScriptRoot 'compose.yaml') ps --quiet postgres)).Trim()
            if ([string]::IsNullOrWhiteSpace($pgCid)) { Fail 'PostgreSQL container must be running to capture an online backup.' }

            $pgPassFile = Join-Path $ScriptRoot 'secrets\postgres-bootstrap-password.txt'
            $metaLine = ([string](& cmd.exe /c "type `"$pgPassFile`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network `"container:$pgCid`" --read-only --cap-drop ALL --security-opt no-new-privileges --user 999:999 --entrypoint sh $pgImg -eu -c `"PGPASSWORD=`$(cat) psql -h 127.0.0.1 -p 5432 -U oscar_bootstrap -d gis -tA -c 'SELECT pg_current_wal_lsn()::text, gen_random_uuid()::text;'`"")).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $metaLine.Contains('|')) { Fail 'Failed querying PostgreSQL LSN.' }
            $parts = $metaLine.Split('|')
            $lsn = $parts[0]; $epochId = $parts[1]

            # 1. Online PostgreSQL pg_basebackup inside WSL2 native volume -> stream tar over stdout (ZERO 9p bind mounts!)
            $pgStageVol = "oscar_usb_pgstage_$randHex"
            & docker volume create $pgStageVol | Out-Null
            & docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --user 0:0 --entrypoint sh `
                --volume "${pgStageVol}:/pgbackup" $pgImg -eu -c 'rm -rf /pgbackup/* && chown 999:999 /pgbackup && chmod 0700 /pgbackup'
            & cmd.exe /c "type `"$pgPassFile`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network `"container:$pgCid`" --read-only --cap-drop ALL --cpus=1 --cpu-shares=128 --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev --user 999:999 --entrypoint sh -v ${pgStageVol}:/pgbackup $pgImg -eu -c `"PGPASSWORD=`$(cat) exec pg_basebackup --pgdata=/pgbackup -h 127.0.0.1 -p 5432 -U oscar_bootstrap --format=plain --wal-method=stream --checkpoint=fast`""
            if ($LASTEXITCODE -ne 0) { Fail 'Online pg_basebackup failed.' }

            & docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --cap-drop ALL --cap-add DAC_READ_SEARCH `
                --cpus=1 --cpu-shares=128 `
                --security-opt no-new-privileges --user 999:999 --entrypoint pg_verifybackup `
                --volume "${pgStageVol}:/pgbackup:ro" `
                $pgImg --quiet /pgbackup
            if ($LASTEXITCODE -ne 0) { Fail 'pg_verifybackup check failed.' }

            $pgTarPath = Join-Path $workDir 'postgres.tar'
            & cmd.exe /c "docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --cpus=1 --cpu-shares=128 --security-opt no-new-privileges --user 0:0 --entrypoint tar -v ${pgStageVol}:/pgbackup:ro $img -C /pgbackup -cf - . > `"$pgTarPath`""
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pgTarPath)) { Fail 'Failed streaming postgres.tar onto USB target.' }
            & docker volume rm -f $pgStageVol 2>$null | Out-Null
            $pgStageVol = $null

            # 2. Native Windows NTFS Incremental Parquet Pack Sync (ZERO WSL2 9p hops!)
            $packIndexList = New-Object System.Collections.Generic.List[string]
            $recentArchiveItems = New-Object System.Collections.Generic.List[string]
            $obsRoot = Join-Path $archiveReal 'datasets\observations'
            if (Test-Path -LiteralPath $obsRoot -PathType Container) {
                foreach ($dir in @(Get-ChildItem -LiteralPath $obsRoot -Directory -Filter 'date=*' | Sort-Object Name)) {
                    $base = $dir.Name
                    $dateStr = $base.Substring('date='.Length)
                    $partials = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.partial*' -ErrorAction SilentlyContinue)
                    if ($dateStr -match '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' -and ([string]::CompareOrdinal($dateStr, $yesterdayUtc) -lt 0) -and $partials.Count -eq 0) {
                        $packName = "archive-$dateStr.tar"
                        $packPath = Join-Path $archivePacksDir $packName
                        $shaPath = "$packPath.sha256"
                        if (-not (Test-Path -LiteralPath $packPath) -or -not (Test-Path -LiteralPath $shaPath)) {
                            $tmpPack = "$packPath.tmp"
                            if (Test-Path -LiteralPath $tmpPack) { Remove-Item -LiteralPath $tmpPack -Force }
                            & $TarExe -C $archiveReal -cf $tmpPack "datasets/observations/$base"
                            if ($LASTEXITCODE -ne 0) { Fail "Failed creating cold archive pack $packName" }
                            Move-Item -LiteralPath $tmpPack -Destination $packPath -Force
                            $sha = Get-FileSha256Lower $packPath
                            [System.IO.File]::WriteAllText($shaPath, "$sha  $packName`n", $Utf8NoBom)
                        } else {
                            $sha = ([System.IO.File]::ReadAllText($shaPath).Split(' ')[0]).Trim()
                        }
                        $packIndexList.Add("$sha  packs/archive/$packName")
                    } else {
                        $recentArchiveItems.Add("datasets/observations/$base")
                    }
                }
            }
            if (Test-Path -LiteralPath $archiveReal -PathType Container) {
                foreach ($entry in @(Get-ChildItem -LiteralPath $archiveReal -Force)) {
                    if ($entry.Name -ceq '.oscar-storage-root' -or $entry.Name -ceq 'datasets') { continue }
                    $recentArchiveItems.Add($entry.Name)
                }
                $dsDir = Join-Path $archiveReal 'datasets'
                if (Test-Path -LiteralPath $dsDir -PathType Container) {
                    foreach ($entry in @(Get-ChildItem -LiteralPath $dsDir -Force)) {
                        if ($entry.Name -ceq 'observations') { continue }
                        $recentArchiveItems.Add("datasets/$($entry.Name)")
                    }
                }
            }
            $archiveRecentTar = Join-Path $workDir 'archive-recent.tar'
            if ($recentArchiveItems.Count -gt 0) {
                & $TarExe -C $archiveReal -cf $archiveRecentTar @recentArchiveItems
                if ($LASTEXITCODE -ne 0) { Fail 'Failed creating archive-recent.tar' }
            } else {
                [System.IO.File]::WriteAllBytes($archiveRecentTar, (New-Object byte[] 10240))
            }

            # 3. Incremental State Volume Delta + Mutable State + Encrypted Secrets via native WSL2 staging volume (ZERO large 9p mounts!)
            $stateStageVol = "oscar_usb_statestage_$randHex"
            & docker volume create $stateStageVol | Out-Null
            $winStageIn = Join-Path $env:TEMP "oscar-usb-in-$randHex"
            $winStageOut = Join-Path $env:TEMP "oscar-usb-out-$randHex"
            New-Item -ItemType Directory -Path $winStageIn, $winStageOut -Force | Out-Null

            $catalogFile = Join-Path $statePacksDir 'catalog.tsv'
            if (Test-Path -LiteralPath $catalogFile) {
                Copy-Item -LiteralPath $catalogFile -Destination (Join-Path $winStageIn 'catalog.tsv') -Force
            } else {
                [System.IO.File]::WriteAllBytes((Join-Path $winStageIn 'catalog.tsv'), [byte[]]@())
            }
            Copy-Item -LiteralPath $keyPath -Destination (Join-Path $winStageIn 'backup-key.txt') -Force
            $depStageDir = Join-Path $winStageIn 'deployment'
            New-Item -ItemType Directory -Path (Join-Path $depStageDir 'secrets'), (Join-Path $depStageDir 'tls') -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $ScriptRoot '.env') -Destination (Join-Path $depStageDir '.env') -Force
            foreach ($s in @('oscar-admin-password.txt', 'oscar-db-password.txt', 'postgres-bootstrap-password.txt')) {
                Copy-Item -LiteralPath (Join-Path $ScriptRoot "secrets\$s") -Destination (Join-Path $depStageDir "secrets\$s") -Force
            }
            foreach ($t in @('server.crt', 'server.key')) {
                Copy-Item -LiteralPath (Join-Path $ScriptRoot "tls\$t") -Destination (Join-Path $depStageDir "tls\$t") -Force
            }
            foreach ($relC in @('.dockerignore', '.env.example', 'DEPLOYMENT.md', 'QUICKSTART.md', 'compose.yaml', 'compose.octelium.yaml',
                'oscar.sh', 'oscar.bat', 'oscar-setup.sh', 'oscar-setup.ps1', 'oscar-storage.sh', 'oscar-storage.ps1',
                'oscar-usb-backup.sh', 'oscar-usb-backup.ps1', 'oscar-usb-backup-engine.sh',
                'configure-ubuntu-host.sh', 'configure-windows-host.ps1', 'validate-storage-archive.sh')) {
                $srcRel = Join-Path $ScriptRoot $relC
                if (Test-Path -LiteralPath $srcRel -PathType Leaf) {
                    Copy-Item -LiteralPath $srcRel -Destination (Join-Path $depStageDir $relC) -Force
                }
            }
            $raDir = Join-Path (Split-Path -Parent $archiveReal) 'remote-access'
            if (Test-Path -LiteralPath (Join-Path $raDir 'octelium.env')) {
                $raStage = Join-Path $winStageIn 'remote-access-src'
                New-Item -ItemType Directory -Path $raStage -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path $raDir 'octelium.env') -Destination (Join-Path $raStage 'octelium.env') -Force
                if (Test-Path -LiteralPath (Join-Path $raDir 'octelium-token.txt')) {
                    Copy-Item -LiteralPath (Join-Path $raDir 'octelium-token.txt') -Destination (Join-Path $raStage 'octelium-token.txt') -Force
                }
            }

            $stateScript = @'
set -Eeuo pipefail
mkdir -p /stage/out /stage/work
export TMPDIR=/stage/work
: >/stage/work/live.tsv
for rel_root in "files/dailyfiles" "files/.dailyfile-journal/segments" "files/videos/retained-media/v1/events" "files/ocr/crops" "files/adjudication" "files/reports" "extensions/maps-storage"; do
    if [[ -d "/state/$rel_root" ]]; then
        (cd /state && find "$rel_root" -ignore_readdir_race -type f -printf '%p\t%s\t%Ts\n' 2>/dev/null) >>/stage/work/live.tsv || true
    fi
done
LC_ALL=C sort -t $'\t' -k1,1 /stage/work/live.tsv -o /stage/work/live.tsv
cut -f1 /stage/work/live.tsv | gzip -1 >/stage/out/live-immutable-paths.txt.gz
wc -l </stage/work/live.tsv | tr -d '[:space:]' >/stage/out/imm-count.txt

LC_ALL=C sort -t $'\t' -k1,1 /stage/catalog.tsv -o /stage/work/catalog.sorted
awk -F'\t' -v OFS='\t' -v delta_out="/stage/work/delta.paths" -v kept_out="/stage/out/kept.tsv" '
    FILENAME == ARGV[1] { cat_size[$1]=$2; cat_mtime[$1]=$3; cat_pack[$1]=$4; next }
    {
        p=$1; sz=$2; mt=$3
        if ((p in cat_pack) && cat_size[p]==sz && cat_mtime[p]==mt) {
            print p, sz, mt, cat_pack[p] > kept_out
        } else {
            print p > delta_out
            print p, sz, mt, "__NEW_PACK__" > kept_out
        }
    }
' /stage/work/catalog.sorted /stage/work/live.tsv
rm -f -- /stage/work/live.tsv /stage/work/catalog.sorted
[[ -f /stage/work/delta.paths ]] || : >/stage/work/delta.paths
[[ -f /stage/out/kept.tsv ]] || : >/stage/out/kept.tsv
if [[ -s /stage/work/delta.paths ]]; then
    (cd /state && tar --ignore-failed-read --warning=no-file-changed --warning=no-file-removed -cf /stage/out/new-state-pack.tar --files-from /stage/work/delta.paths) || {
        rc=$?; ((rc <= 1)) || exit "$rc"
    }
    printf '1\n' >/stage/out/has-new-pack.txt
fi
rm -f -- /stage/work/delta.paths
(
    cd /state
    tar --ignore-failed-read --warning=no-file-changed --warning=no-file-removed \
        --exclude='./archive' --exclude='./backups' --exclude='./duckdb-tmp' \
        --exclude='./lib' --exclude='./web' --exclude='./rules' --exclude='./models' \
        --exclude='./documentation' --exclude='./trusted_certificates' --exclude='./config' \
        --exclude='./logback.xml' --exclude='./.cache' --exclude='./logs' \
        --exclude='./.moduledata/usb-backup-control' \
        --exclude='./files/videos/clips' --exclude='./files/videos/streams' \
        --exclude='./files/dailyfiles' --exclude='./files/.dailyfile-journal/segments' \
        --exclude='./files/videos/retained-media/v1/events' \
        --exclude='./files/ocr/crops' --exclude='./files/adjudication' --exclude='./files/reports' --exclude='./extensions/maps-storage' \
        -cf /stage/out/mutable-state.tar .
) || { mrc=$?; ((mrc <= 1)) || exit "$mrc"; }

mkdir -p /tmp/work/sec/secrets /tmp/work/sec/tls
cp -f /stage/deployment/.env /tmp/work/sec/.env
cp -f /stage/backup-key.txt /tmp/work/sec/secrets/backup-key.txt
for s in oscar-admin-password.txt oscar-db-password.txt postgres-bootstrap-password.txt; do
    cp -f "/stage/deployment/secrets/$s" "/tmp/work/sec/secrets/$s"
done
cp -f /stage/deployment/tls/server.crt /stage/deployment/tls/server.key /tmp/work/sec/tls/
if [[ -d /stage/remote-access-src && -f /stage/remote-access-src/octelium.env && ! -L /stage/remote-access-src/octelium.env ]]; then
    mkdir -p /tmp/work/sec/remote-access
    cp -f /stage/remote-access-src/octelium.env /tmp/work/sec/remote-access/octelium.env
    [[ -f /stage/remote-access-src/octelium-token.txt && ! -L /stage/remote-access-src/octelium-token.txt ]] && cp -f /stage/remote-access-src/octelium-token.txt /tmp/work/sec/remote-access/octelium-token.txt || true
fi
tar -C /tmp/work/sec -czf /tmp/work/sec.tar.gz .
openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:/stage/backup-key.txt -in /tmp/work/sec.tar.gz -out /stage/out/deployment-secrets.tar.gz.enc

rel_files=()
for c in .dockerignore .env.example DEPLOYMENT.md QUICKSTART.md compose.yaml compose.octelium.yaml \
    oscar.sh oscar.bat oscar-setup.sh oscar-setup.ps1 oscar-storage.sh oscar-storage.ps1 \
    oscar-usb-backup.sh oscar-usb-backup.ps1 oscar-usb-backup-engine.sh \
    configure-ubuntu-host.sh configure-windows-host.ps1 validate-storage-archive.sh; do
    [[ -f "/stage/deployment/$c" ]] && rel_files+=("$c")
done
tar -C /stage/deployment -czf /stage/out/release-config.tar.gz "${rel_files[@]}"
meta_items=(live-immutable-paths.txt.gz imm-count.txt kept.tsv deployment-secrets.tar.gz.enc release-config.tar.gz)
[[ -f /stage/out/has-new-pack.txt ]] && meta_items+=(has-new-pack.txt)
tar --format=ustar -C /stage/out -cf /stage/out/meta.tar "${meta_items[@]}"
'@
            [System.IO.File]::WriteAllText((Join-Path $winStageIn 'run.sh'), $stateScript.Replace("`r`n", "`n"), $Utf8NoBom)
            & cmd.exe /c "`"$TarExe`" -C `"$winStageIn`" -cf - . | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --user 0:0 -v ${stateStageVol}:/stage --entrypoint tar $img -C /stage -xf -"
            if ($LASTEXITCODE -ne 0) { Fail 'Failed seeding state catalog into staging volume.' }

            $dockerArgs = @(
                'run', '--rm',
                '--label', 'com.docker.compose.project=oscar-usb-backup',
                '--label', 'com.docker.compose.service=usb-backup-engine',
                '--network', 'none', '--read-only', '--security-opt', 'no-new-privileges',
                '--cpus=1', '--cpu-shares=128',
                '--tmpfs', '/tmp:rw,noexec,nosuid,nodev,size=1024m',
                '--user', '0:0', '--entrypoint', 'bash',
                '--volume', 'oscar_oscar_state:/state:ro',
                '--volume', "${stateStageVol}:/stage",
                $img, '/stage/run.sh'
            )
            & docker @dockerArgs
            if ($LASTEXITCODE -ne 0) { Fail 'Container state delta capture failed.' }

            $copyHolderCid = ([string](& docker create --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none -v "${stateStageVol}:/stage:ro" $img)).Trim()
            if ([string]::IsNullOrWhiteSpace($copyHolderCid)) { Fail 'Failed creating staging copy container.' }
            try {
                $metaTarHost = Join-Path $winStageOut 'meta.tar'
                & docker cp "${copyHolderCid}:/stage/out/meta.tar" $metaTarHost
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $metaTarHost)) { Fail 'Failed copying state metadata archive onto host.' }
                & $TarExe -C $winStageOut -xf $metaTarHost
                if ($LASTEXITCODE -ne 0) { Fail 'Failed extracting state metadata archive on host.' }
                Remove-Item -LiteralPath $metaTarHost -Force -ErrorAction SilentlyContinue

                $mutTarDest = Join-Path $workDir 'mutable-state.tar'
                & docker cp "${copyHolderCid}:/stage/out/mutable-state.tar" $mutTarDest
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $mutTarDest)) { Fail 'Failed copying mutable-state.tar onto USB target.' }

                $keptContent = [System.IO.File]::ReadAllText((Join-Path $winStageOut 'kept.tsv'))
                if (Test-Path -LiteralPath (Join-Path $winStageOut 'has-new-pack.txt')) {
                    $existingToday = @(Get-ChildItem -LiteralPath $statePacksDir -File -Filter "pack-$todayUtc-*.tar" -ErrorAction SilentlyContinue | Sort-Object Name)
                    $nextSeq = 1
                    if ($existingToday.Count -gt 0 -and $existingToday[-1].Name -match '^pack-[0-9-]+-([0-9]{6})\.tar$') {
                        $nextSeq = [int]$Matches[1] + 1
                    }
                    $newPackName = ('pack-{0}-{1:D6}.tar' -f $todayUtc, $nextSeq)
                    $newPackDest = Join-Path $statePacksDir $newPackName
                    & docker cp "${copyHolderCid}:/stage/out/new-state-pack.tar" $newPackDest
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $newPackDest)) { Fail 'Failed copying new-state-pack.tar onto USB target.' }
                    $npSha = Get-FileSha256Lower $newPackDest
                    [System.IO.File]::WriteAllText("$newPackDest.sha256", "$npSha  $newPackName`n", $Utf8NoBom)
                    $keptContent = $keptContent.Replace('__NEW_PACK__', $newPackName)
                }
            } finally {
                & docker rm -f $copyHolderCid 2>$null | Out-Null
            }
            & docker volume rm -f $stateStageVol 2>$null | Out-Null
            $stateStageVol = $null
            [System.IO.File]::WriteAllText($catalogFile, $keptContent, $Utf8NoBom)

            # Collect referenced state packs & garbage-collect unreferenced state packs
            $refSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($line in [System.IO.File]::ReadAllLines($catalogFile)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $cols = $line.Split("`t")
                if ($cols.Count -ge 4) { [void]$refSet.Add($cols[3].Trim()) }
            }
            foreach ($sp in @(Get-ChildItem -LiteralPath $statePacksDir -File -Filter 'pack-*.tar' -ErrorAction SilentlyContinue | Sort-Object Name)) {
                if ($refSet.Contains($sp.Name)) {
                    $shaFile = "$($sp.FullName).sha256"
                    if (-not (Test-Path -LiteralPath $shaFile)) {
                        $s = Get-FileSha256Lower $sp.FullName
                        [System.IO.File]::WriteAllText($shaFile, "$s  $($sp.Name)`n", $Utf8NoBom)
                    }
                    $spSha = ([System.IO.File]::ReadAllText($shaFile).Split(' ')[0]).Trim()
                    $packIndexList.Add("$spSha  packs/state/$($sp.Name)")
                } else {
                    Remove-Item -LiteralPath $sp.FullName -Force -ErrorAction SilentlyContinue
                    Remove-Item -LiteralPath "$($sp.FullName).sha256" -Force -ErrorAction SilentlyContinue
                }
            }

            foreach ($fname in @('live-immutable-paths.txt.gz', 'deployment-secrets.tar.gz.enc', 'release-config.tar.gz')) {
                Move-Item -LiteralPath (Join-Path $winStageOut $fname) -Destination (Join-Path $workDir $fname) -Force
            }
            $immCount = [int]([System.IO.File]::ReadAllText((Join-Path $winStageOut 'imm-count.txt')).Trim())

            $sortedPackIndex = @($packIndexList | Sort-Object { $_.Substring(66) })
            $packIndexBody = if ($sortedPackIndex.Count -gt 0) { ($sortedPackIndex -join "`n") + "`n" } else { '' }
            [System.IO.File]::WriteAllText((Join-Path $workDir 'pack-index.txt'), $packIndexBody, $Utf8NoBom)

            $archPackCount = @($sortedPackIndex | Where-Object { $_ -like '*  packs/archive/*' }).Count
            $stPackCount = @($sortedPackIndex | Where-Object { $_ -like '*  packs/state/*' }).Count
            $epochJson = @"
{
  "format": "oscar-usb-incremental-backup",
  "version": 1,
  "backupEpochId": "$epochId",
  "snapshotId": "$snapId",
  "deploymentId": "$depId",
  "oscarVersion": "$ver",
  "backupMode": "$($cfg.mode)",
  "createdAt": "$tsIso",
  "postgresLsn": "$lsn",
  "archivePackCount": $archPackCount,
  "statePackCount": $stPackCount,
  "immutableStateFileCount": $immCount
}
"@.Replace("`r`n", "`n") + "`n"
            [System.IO.File]::WriteAllText((Join-Path $workDir 'epoch.json'), $epochJson, $Utf8NoBom)

            # 4. Native SHA256SUMS + HMAC-SHA256 + Atomic LATEST Commit
            $sumLines = New-Object System.Collections.Generic.List[string]
            foreach ($f in @(Get-ChildItem -LiteralPath $workDir -File | Where-Object { $_.Name -cnotin @('SHA256SUMS', 'SHA256SUMS.hmac', 'VERIFIED') } | Sort-Object Name)) {
                $h = Get-FileSha256Lower $f.FullName
                $sumLines.Add("$h  ./$($f.Name)")
            }
            $sumsPath = Join-Path $workDir 'SHA256SUMS'
            [System.IO.File]::WriteAllText($sumsPath, (($sumLines -join "`n") + "`n"), $Utf8NoBom)
            $sumsMac = Get-HmacBase64 ([System.IO.File]::ReadAllBytes($sumsPath)) $keyPath
            [System.IO.File]::WriteAllText((Join-Path $workDir 'SHA256SUMS.hmac'), "$sumsMac`n", $Utf8NoBom)

            $finalSnapDir = Join-Path $snapshotsDir $snapId
            Move-Item -LiteralPath $workDir -Destination $finalSnapDir -Force
            [System.IO.File]::WriteAllText((Join-Path $finalSnapDir 'VERIFIED'), "verified_at=$tsIso`nsnapshot_id=$snapId`n", $Utf8NoBom)

            $latestBody = "format=oscar-usb-latest`nversion=1`nsnapshot_id=$snapId`n"
            $latestMac = Get-HmacBase64 ($Utf8NoBom.GetBytes($latestBody)) $keyPath
            $latestTmp = Join-Path $backupRoot ".LATEST.tmp.$randHex"
            [System.IO.File]::WriteAllText($latestTmp, "${latestBody}hmac_sha256=$latestMac`n", $Utf8NoBom)
            Move-Item -LiteralPath $latestTmp -Destination (Join-Path $backupRoot 'LATEST') -Force

            foreach ($oldDir in @(Get-ChildItem -LiteralPath $snapshotsDir -Directory | Where-Object { $_.Name -cne $snapId })) {
                Remove-Item -LiteralPath $oldDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }

            Invoke-Verify @('-From', $targetRoot, '-BackupKey', $keyPath) | Out-Null
        } finally {
            if ($quiesce) {
                Invoke-Compose @('up', '--detach', '--no-build', '--pull', 'never', '--wait', '--wait-timeout', '240', 'oscar', 'gateway')
            }
        }
        $dtLabel = if ($quiesce) { 'brief quiesce' } else { '0s - remained online' }
        Write-Host "Incremental backup sync COMPLETE: snapshot=$snapId (portal downtime: $dtLabel)" -ForegroundColor Green
    } finally {
        if ($pgStageVol) { & docker volume rm -f $pgStageVol 2>$null | Out-Null }
        if ($stateStageVol) { & docker volume rm -f $stateStageVol 2>$null | Out-Null }
        if ($winStageIn) { Remove-Item -LiteralPath $winStageIn -Recurse -Force -ErrorAction SilentlyContinue }
        if ($winStageOut) { Remove-Item -LiteralPath $winStageOut -Recurse -Force -ErrorAction SilentlyContinue }
        $lockStream.Dispose()
    }
    Write-AgentStatusJson $null
}

function Invoke-Eject([string[]]$Tokens) {
    Assert-Administrator
    $cfg = Read-UsbConfig
    if ($null -eq $cfg) { Fail 'No USB backup drive is configured.' }
    $noSync = $false
    foreach ($t in $Tokens) {
        if ($t -match '^(-NoSync|--no-sync)$') { $noSync = $true }
        else { Fail "Unknown eject option: $t" }
    }

    if (-not (Test-DriveAttached $cfg)) {
        Write-AgentStatusJson $null
        Write-Host "USB backup drive ($($cfg.targetPath)) is already ejected / detached. Safe to unplug." -ForegroundColor Green
        return
    }
    if (-not $noSync) {
        Write-Heading 'Running final delta sync before safe USB eject'
        Invoke-Sync @()
    }

    $lockStream = Acquire-StorageLock
    try {
        $dl = ([string]$cfg.driveLetter -replace ':','').Trim()
        if (-not [string]::IsNullOrWhiteSpace($dl)) {
            Write-VolumeCache -DriveLetter $dl -ErrorAction SilentlyContinue | Out-Null
            if ([int]$cfg.diskNumber -ge 0) {
                $disk = Get-Disk -Number ([int]$cfg.diskNumber) -ErrorAction SilentlyContinue
                if ($disk -and $disk.BusType -eq 'USB') {
                    Set-Disk -Number ([int]$cfg.diskNumber) -IsOffline $true
                } else {
                    [System.IO.File]::WriteAllText((Join-Path ([string]$cfg.targetPath) '.oscar-ejected'), "ejected`n", $Utf8NoBom)
                }
            }
        } else {
            [System.IO.File]::WriteAllText((Join-Path ([string]$cfg.targetPath) '.oscar-ejected'), "ejected`n", $Utf8NoBom)
        }
    } finally {
        $lockStream.Dispose()
    }
    Write-AgentStatusJson $null

    Write-Host @"

================================================================================
SAFE TO UNPLUG: $($cfg.targetPath) has been flushed and cleanly prepared for removal.
- OSCAR remains 100% online and continues recording on internal NVMe storage.
- Plug the USB NVMe SSD into your laptop and run COPY-TO-ANOTHER-DRIVE.bat
  (Windows) or ./copy-to-another-drive.sh (macOS/Linux) to copy new packs.
- When finished, plug the USB NVMe SSD back into the OSCAR USB 3.x port
  (and run .\oscar.bat usb-backup attach, or let continual mode catch up).
================================================================================
"@ -ForegroundColor Green
}

function Invoke-Attach {
    Assert-Administrator
    $cfg = Read-UsbConfig
    if ($null -eq $cfg) { Fail 'No USB backup drive is configured.' }
    if ([int]$cfg.diskNumber -ge 0) {
        $disk = Get-Disk -Number ([int]$cfg.diskNumber) -ErrorAction SilentlyContinue
        if ($disk -and $disk.IsOffline) {
            Set-Disk -Number ([int]$cfg.diskNumber) -IsOffline $false
            Start-Sleep -Seconds 2
        }
    }
    $ej = Join-Path ([string]$cfg.targetPath) '.oscar-ejected'
    if (Test-Path -LiteralPath $ej) { Remove-Item -LiteralPath $ej -Force }
    if (-not (Test-DriveAttached $cfg)) {
        Fail "Drive at $($cfg.targetPath) is not reachable or missing OSCAR-Backup\.oscar-usb-backup-root."
    }
    Write-Heading 'USB backup drive attached - pulling in all data recorded while disconnected'
    Invoke-Sync @()
}

function Invoke-Status {
    Write-Heading 'OSCAR Continual / USB NVMe Backup Status'
    $cfg = Read-UsbConfig
    if ($null -eq $cfg) {
        Write-Host 'Status: UNCONFIGURED (run .\oscar.bat usb-backup prepare-drive ... to set up)'
        return
    }
    Write-Host "Configured Mode:       $($cfg.mode) (interval=$($cfg.intervalMinutes) min)"
    Write-Host "Target Path:           $($cfg.targetPath)"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    $taskState = if ($task) { [string]$task.State } else { 'NotRegistered' }
    Write-Host "Scheduled Task State:  $taskState"
    if (Test-DriveAttached $cfg) {
        Write-Host 'Drive State:           ATTACHED' -ForegroundColor Green
        $latestFile = Join-Path ([string]$cfg.targetPath) 'OSCAR-Backup\LATEST'
        if (Test-Path -LiteralPath $latestFile) {
            $snapId = Get-EnvFileValue $latestFile 'snapshot_id' ''
            Write-Host "Latest Verified Point: $snapId"
            $epochFile = Join-Path ([string]$cfg.targetPath) "OSCAR-Backup\snapshots\$snapId\epoch.json"
            if (Test-Path -LiteralPath $epochFile) {
                $ep = Get-Content -LiteralPath $epochFile -Raw | ConvertFrom-Json
                Write-Host "Snapshot UTC Time:     $($ep.createdAt)"
                Write-Host "PostgreSQL LSN:        $($ep.postgresLsn)"
                Write-Host "Sealed Archive Packs:  $($ep.archivePackCount)"
                Write-Host "State Media/CSV Packs: $($ep.statePackCount)"
            }
        }
    } else {
        Write-Host 'Drive State:           DETACHED / UNPLUGGED (OSCAR continues recording normally; reconnect to catch up)' -ForegroundColor Yellow
    }
}

function Invoke-Verify([string[]]$Tokens) {
    Assert-Administrator
    $fromPath = ''
    $keyPath = ''
    $deep = $false
    $i = 0
    while ($i -lt $Tokens.Count) {
        switch -Regex ($Tokens[$i]) {
            '^(-From|--from)$'            { $fromPath = $Tokens[$i + 1]; $i += 2; continue }
            '^(-BackupKey|--backup-key)$' { $keyPath = $Tokens[$i + 1]; $i += 2; continue }
            '^(-Deep|--deep)$'            { $deep = $true; $i += 1; continue }
            default { Fail "Unknown verify option: $($Tokens[$i])" }
        }
    }
    if ([string]::IsNullOrWhiteSpace($fromPath)) {
        $cfg = Read-UsbConfig
        if ($cfg) { $fromPath = [string]$cfg.targetPath }
    }
    $backupRoot = Join-Path $fromPath 'OSCAR-Backup'
    if ([string]::IsNullOrWhiteSpace($fromPath) -or -not (Test-Path -LiteralPath (Join-Path $backupRoot 'LATEST'))) {
        Fail "OSCAR-Backup\LATEST not found under: $fromPath"
    }
    if ([string]::IsNullOrWhiteSpace($keyPath)) { $keyPath = Join-Path $ScriptRoot 'secrets\backup-key.txt' }
    if (-not (Test-Path -LiteralPath $keyPath)) { Fail "Backup key file not found: $keyPath" }
    $keyFull = [System.IO.Path]::GetFullPath($keyPath)

    # 1. Native PowerShell HMAC & SHA-256 verification (ZERO 9p overhead!)
    $latestClean = ([System.IO.File]::ReadAllText((Join-Path $backupRoot 'LATEST'))).Replace("`r`n", "`n")
    $latestLines = @($latestClean -split "`n" | Where-Object { $_ -ne '' })
    if ($latestLines.Count -lt 4) { Fail 'Malformed LATEST pointer.' }
    $latestBody = ($latestLines[0..2] -join "`n") + "`n"
    $snapId = Get-EnvFileValue (Join-Path $backupRoot 'LATEST') 'snapshot_id' ''
    $expectedLatestMac = Get-EnvFileValue (Join-Path $backupRoot 'LATEST') 'hmac_sha256' ''
    if ($snapId -notmatch '^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}$') { Fail "Invalid snapshot_id in LATEST: $snapId" }
    $actualLatestMac = Get-HmacBase64 ($Utf8NoBom.GetBytes($latestBody)) $keyFull
    if ($actualLatestMac -cne $expectedLatestMac) {
        Fail 'LATEST pointer HMAC authentication failed (wrong backup-key.txt or tampered pointer).'
    }

    $snapDir = Join-Path $backupRoot "snapshots\$snapId"
    $sumsPath = Join-Path $snapDir 'SHA256SUMS'
    $sumsHmacPath = Join-Path $snapDir 'SHA256SUMS.hmac'
    if (-not (Test-Path -LiteralPath $sumsPath) -or -not (Test-Path -LiteralPath $sumsHmacPath)) {
        Fail "Missing SHA256SUMS or SHA256SUMS.hmac in $snapDir"
    }
    $expectedSumsMac = ([System.IO.File]::ReadAllText($sumsHmacPath)).Trim()
    $actualSumsMac = Get-HmacBase64 ([System.IO.File]::ReadAllBytes($sumsPath)) $keyFull
    if ($actualSumsMac -cne $expectedSumsMac) {
        Fail "Snapshot $snapId SHA256SUMS.hmac authentication failed."
    }
    foreach ($line in [System.IO.File]::ReadAllLines($sumsPath)) {
        if ($line -match '^([0-9a-f]{64})  \./(.+)$') {
            $targetFile = Join-Path $snapDir ($Matches[2] -replace '/','\')
            if (-not (Test-Path -LiteralPath $targetFile)) { Fail "Missing snapshot file: $targetFile" }
            if ((Get-FileSha256Lower $targetFile) -cne $Matches[1]) { Fail "SHA-256 mismatch: $targetFile" }
        }
    }
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $snapDir 'pack-index.txt'))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^([0-9a-f]{64})  (.+)$') {
            $fullPack = Join-Path $backupRoot ($Matches[2] -replace '/','\')
            if (-not (Test-Path -LiteralPath $fullPack)) { Fail "Referenced pack is missing: $fullPack" }
            if ($deep) {
                if ((Get-FileSha256Lower $fullPack) -cne $Matches[1]) { Fail "Deep SHA-256 mismatch in pack: $fullPack" }
            } elseif (Test-Path -LiteralPath "$fullPack.sha256") {
                $recSha = ([System.IO.File]::ReadAllText("$fullPack.sha256").Split(' ')[0]).Trim()
                if ($recSha -cne $Matches[1]) { Fail "Pack sidecar SHA-256 mismatch: $fullPack" }
            }
        }
    }

    # 2. Verify secret archive decryptability & pg_verifybackup via stdin streaming (ZERO 9p bind mounts!)
    $ver = Get-OscarVersion
    $encFile = Join-Path $snapDir 'deployment-secrets.tar.gz.enc'
    $verifySecStage = Join-Path $env:TEMP "oscar-usb-vsec-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $verifySecStage -Force | Out-Null
    try {
        Copy-Item -LiteralPath $keyFull -Destination (Join-Path $verifySecStage 'backup-key.txt') -Force
        Copy-Item -LiteralPath $encFile -Destination (Join-Path $verifySecStage 'secrets.enc') -Force
        & cmd.exe /c "`"$TarExe`" -C `"$verifySecStage`" -cf - . | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --read-only --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m --user 0:0 --entrypoint sh oscar:$ver -eu -c `"mkdir -p /tmp/in /tmp/s && tar -C /tmp/in -xf - && openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/tmp/in/backup-key.txt -in /tmp/in/secrets.enc | tar -C /tmp/s -xzf - && test -f /tmp/s/.env && test -f /tmp/s/tls/server.crt && test -f /tmp/s/tls/server.key`""
        if ($LASTEXITCODE -ne 0) { Fail 'Decrypted secret archive check failed.' }
    } finally {
        Remove-Item -LiteralPath $verifySecStage -Recurse -Force -ErrorAction SilentlyContinue
    }

    $pgTar = Join-Path $snapDir 'postgres.tar'
    $pgVerifyVol = "oscar_usb_pgverify_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    try {
        & docker volume create $pgVerifyVol | Out-Null
        & cmd.exe /c "type `"$pgTar`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --read-only --security-opt no-new-privileges --user 0:0 --entrypoint sh -v ${pgVerifyVol}:/pgbackup oscar:$ver -eu -c `"tar -C /pgbackup --no-same-owner -xf - && chown -R 999:999 /pgbackup`""
        if ($LASTEXITCODE -ne 0) { Fail 'Failed staging postgres.tar for verification.' }
        & docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --cap-drop ALL --cap-add DAC_READ_SEARCH `
            --security-opt no-new-privileges --user 999:999 --entrypoint pg_verifybackup `
            --volume "${pgVerifyVol}:/pgbackup:ro" `
            "oscar-postgis:$ver" --quiet /pgbackup
        if ($LASTEXITCODE -ne 0) { Fail 'pg_verifybackup check failed.' }
    } finally {
        & docker volume rm -f $pgVerifyVol 2>$null | Out-Null
    }
    Write-Host "VERIFIED OK: USB incremental backup snapshot $snapId (HMAC, SHA-256 manifests, packs, secrets, and pg_verifybackup all valid)." -ForegroundColor Green
}

function Invoke-Restore([string[]]$Tokens) {
    Assert-Administrator
    $fromPath = ''
    $keyPath = ''
    $archiveDir = ''
    $confirm = ''
    $i = 0
    while ($i -lt $Tokens.Count) {
        switch -Regex ($Tokens[$i]) {
            '^(-From|--from)$'              { $fromPath = $Tokens[$i + 1]; $i += 2; continue }
            '^(-BackupKey|--backup-key)$'   { $keyPath = $Tokens[$i + 1]; $i += 2; continue }
            '^(-ArchiveDir|--archive-dir)$' { $archiveDir = $Tokens[$i + 1]; $i += 2; continue }
            '^(-Confirm|--confirm)$'        { $confirm = $Tokens[$i + 1]; $i += 2; continue }
            default { Fail "Unknown restore option: $($Tokens[$i])" }
        }
    }
    if ($confirm -cne 'RESTORE') { Fail 'Restore overwrites target PostgreSQL, state, archive, and credentials. Re-run with -Confirm RESTORE' }
    if ([string]::IsNullOrWhiteSpace($fromPath)) {
        $cfg = Read-UsbConfig
        if ($cfg) { $fromPath = [string]$cfg.targetPath }
    }
    $fromFull = [System.IO.Path]::GetFullPath($fromPath)
    $backupRoot = Join-Path $fromFull 'OSCAR-Backup'
    if ([string]::IsNullOrWhiteSpace($keyPath)) { $keyPath = Join-Path $ScriptRoot 'secrets\backup-key.txt' }
    $keyFull = [System.IO.Path]::GetFullPath($keyPath)

    $ver = Get-OscarVersion
    $offlineTar = Join-Path $ScriptRoot 'offline-images.tar'
    & docker image inspect "oscar:$ver" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath $offlineTar)) {
        Write-Heading 'Loading offline container images on replacement host'
        & docker load --input $offlineTar | Out-Null
    }

    Write-Heading 'Step 1/5 - Deep-verifying USB backup cryptographic HMAC, packs & PostgreSQL base backup'
    Invoke-Verify @('-From', $fromFull, '-BackupKey', $keyFull, '-Deep')
    $snapId = Get-EnvFileValue (Join-Path $backupRoot 'LATEST') 'snapshot_id' ''
    $snapDir = Join-Path $backupRoot "snapshots\$snapId"

    $credsStage = Join-Path $env:TEMP "oscar-usb-creds-$([Guid]::NewGuid().ToString('N'))"
    $credsIn = Join-Path $env:TEMP "oscar-usb-credin-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $credsStage, $credsIn -Force | Out-Null
    try {
        $encFile = Join-Path $snapDir 'deployment-secrets.tar.gz.enc'
        Copy-Item -LiteralPath $keyFull -Destination (Join-Path $credsIn 'backup-key.txt') -Force
        Copy-Item -LiteralPath $encFile -Destination (Join-Path $credsIn 'secrets.enc') -Force
        & cmd.exe /c "`"$TarExe`" -C `"$credsIn`" -cf - . | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --read-only --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m --user 0:0 --entrypoint sh oscar:$ver -eu -c `"mkdir -p /tmp/in /tmp/s && tar -C /tmp/in -xf - && openssl enc -d -aes-256-cbc -pbkdf2 -pass file:/tmp/in/backup-key.txt -in /tmp/in/secrets.enc | tar -C /tmp/s --no-same-owner -xzf - && tar -C /tmp/s -cf - .`" | `"$TarExe`" -C `"$credsStage`" -xf -"
        if ($LASTEXITCODE -ne 0) { Fail 'Failed decrypting deployment credentials.' }

        $restoredDepId = Get-EnvFileValue (Join-Path $credsStage '.env') 'OSCAR_DEPLOYMENT_ID' ''
        if ([string]::IsNullOrWhiteSpace($restoredDepId)) { Fail 'Restored .env is missing OSCAR_DEPLOYMENT_ID.' }

        if (Test-Path -LiteralPath (Join-Path $ScriptRoot '.env')) {
            try { Invoke-Compose @('stop', 'gateway', 'oscar', 'postgres') } catch {}
        }

        Write-Heading 'Step 2/5 - Installing restored credentials, storage roots & deployment-labeled volumes'
        $targetArchive = Resolve-ArchiveDirectory $archiveDir
        $envLines = [System.IO.File]::ReadAllLines((Join-Path $credsStage '.env')) | Where-Object {
            $_ -notmatch '^(OSCAR_BACKUP_DIR|OSCAR_WAL_ARCHIVE_DIR)='
        } | ForEach-Object {
            if ($_ -like 'OSCAR_ARCHIVE_DIR=*') { "OSCAR_ARCHIVE_DIR=$targetArchive" }
            elseif ($_ -like 'OSCAR_VERSION=*') { "OSCAR_VERSION=$ver" }
            elseif ($_ -like 'OSCAR_BACKUP_MODE=*') { 'OSCAR_BACKUP_MODE=disabled' }
            else { $_ }
        }
        [System.IO.File]::WriteAllText((Join-Path $ScriptRoot '.env'), (($envLines -join "`n") + "`n"), $Utf8NoBom)
        foreach ($sub in @('secrets', 'tls')) {
            $dst = Join-Path $ScriptRoot $sub
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
            Copy-Item -LiteralPath (Join-Path $credsStage $sub) -Destination $dst -Recurse -Force
        }

        foreach ($vol in @('oscar_oscar_state', 'oscar_postgres_data')) {
            & docker volume rm -f $vol 2>$null | Out-Null
            & docker volume create --label "com.botts.oscar.deployment-id=$restoredDepId" $vol | Out-Null
        }
        if (-not (Test-Path -LiteralPath $targetArchive)) {
            New-Item -ItemType Directory -Path $targetArchive -Force | Out-Null
        } else {
            Get-ChildItem -LiteralPath $targetArchive -Force | Where-Object { $_.Name -cne '.oscar-storage-root' } | Remove-Item -Recurse -Force
        }
        $claimedNow = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $archMarkerPath = Join-Path $targetArchive '.oscar-storage-root'
        $archMarker = @(
            'format=oscar-storage-root-identity',
            'version=1',
            "deployment_id=$restoredDepId",
            'root_kind=archive',
            'adoption=new',
            "claimed_at=$claimedNow",
            'adopted_at=none',
            'adopted_by=none'
        ) -join "`n"
        [System.IO.File]::WriteAllText($archMarkerPath, "$archMarker`n", $Utf8NoBom)
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $winIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $adminsSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
            $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
            $allowType = [Security.AccessControl.AccessControlType]::Allow
            $fullRights = [Security.AccessControl.FileSystemRights]::FullControl
            $inheritFlags = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
            $propFlags = [Security.AccessControl.PropagationFlags]::None

            $dirAcl = New-Object Security.AccessControl.DirectorySecurity
            $dirAcl.SetOwner($adminsSid)
            $dirAcl.SetAccessRuleProtection($true, $false)
            foreach ($p in @($winIdentity.User, $systemSid, $adminsSid)) {
                [void]$dirAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($p, $fullRights, $inheritFlags, $propFlags, $allowType))
            }
            foreach ($grpName in @("$env:COMPUTERNAME\docker-users", 'docker-users')) {
                try {
                    $dockerSid = ([Security.Principal.NTAccount]::new($grpName)).Translate([Security.Principal.SecurityIdentifier])
                    [void]$dirAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($dockerSid, [Security.AccessControl.FileSystemRights]::Modify, $inheritFlags, $propFlags, $allowType))
                    break
                } catch {}
            }
            Set-Acl -LiteralPath $targetArchive -AclObject $dirAcl

            $fileAcl = New-Object Security.AccessControl.FileSecurity
            $fileAcl.SetOwner($adminsSid)
            $fileAcl.SetAccessRuleProtection($true, $false)
            foreach ($p in @($winIdentity.User, $systemSid, $adminsSid)) {
                [void]$fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($p, $fullRights, $allowType))
            }
            Set-Acl -LiteralPath $archMarkerPath -AclObject $fileAcl
        }

        Write-Heading 'Step 3/5 - Extracting cold Parquet archive packs & OSCAR application state'
        foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $snapDir 'pack-index.txt'))) {
            if ($line -match '^[0-9a-f]{64}  (packs/archive/.+\.tar)$') {
                $packFull = Join-Path $backupRoot ($Matches[1] -replace '/','\')
                & $TarExe -C $targetArchive -xf $packFull
                if ($LASTEXITCODE -ne 0) { Fail "Failed extracting $packFull" }
            }
        }
        $archRecent = Join-Path $snapDir 'archive-recent.tar'
        if (Test-Path -LiteralPath $archRecent) {
            & $TarExe -C $targetArchive -xf $archRecent
            if ($LASTEXITCODE -ne 0) { Fail 'Failed extracting archive-recent.tar' }
        }

        & docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --user 0:0 -v 'oscar_oscar_state:/state' --entrypoint sh "oscar:$ver" -eu -c 'find /state -mindepth 1 -maxdepth 1 ! -name archive -exec rm -rf -- {} +'
        $mutTar = Join-Path $snapDir 'mutable-state.tar'
        & cmd.exe /c "type `"$mutTar`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --user 0:0 -v oscar_oscar_state:/state --entrypoint tar oscar:$ver -C /state --no-same-owner -xf -"
        if ($LASTEXITCODE -ne 0) { Fail 'Failed extracting mutable-state.tar' }

        foreach ($line in @([System.IO.File]::ReadAllLines((Join-Path $snapDir 'pack-index.txt')) | Where-Object { $_ -like '*  packs/state/*' } | Sort-Object { $_.Substring(66) })) {
            if ($line -match '^[0-9a-f]{64}  (packs/state/.+\.tar)$') {
                $packFull = Join-Path $backupRoot ($Matches[1] -replace '/','\')
                & cmd.exe /c "type `"$packFull`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --user 0:0 -v oscar_oscar_state:/state --entrypoint tar oscar:$ver -C /state --no-same-owner -xf -"
                if ($LASTEXITCODE -ne 0) { Fail "Failed extracting $packFull" }
            }
        }
        $liveImmGz = Join-Path $snapDir 'live-immutable-paths.txt.gz'
        $restoreScratchVol = "oscar_usb_rscratch_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        & docker volume create $restoreScratchVol | Out-Null
        try {
            & cmd.exe /c "type `"$liveImmGz`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --tmpfs /tmp:rw,noexec,nosuid,nodev,size=1024m --user 0:0 -v oscar_oscar_state:/state -v ${restoreScratchVol}:/scratch --entrypoint bash oscar:$ver -eu -c `"export TMPDIR=/scratch && gzip -dc | LC_ALL=C sort -u >/scratch/exp && : >/scratch/ext && for r in 'files/dailyfiles' 'files/.dailyfile-journal/segments' 'files/videos/retained-media/v1/events' 'files/ocr/crops' 'files/adjudication' 'files/reports' 'extensions/maps-storage'; do if [ -d /state/`$r ]; then (cd /state && find `$r -type f -printf '%p\n' 2>/dev/null) >>/scratch/ext || true; fi; done && LC_ALL=C sort -u /scratch/ext -o /scratch/ext && LC_ALL=C comm -23 /scratch/ext /scratch/exp >/scratch/prune && if [ -s /scratch/prune ]; then (cd /state && xargs -d '\n' rm -f -- </scratch/prune); fi && for l in lib web rules models documentation trusted_certificates config logback.xml; do rm -rf /state/`$l && ln -s /opt/oscar/`$l /state/`$l; done && chown -R 10001:10001 /state && if [ -f /state/config.json ]; then chmod 0600 /state/config.json; fi`""
            if ($LASTEXITCODE -ne 0) { Fail 'Failed finalizing restored OSCAR state volume.' }
        } finally {
            & docker volume rm -f $restoreScratchVol 2>$null | Out-Null
        }

        Write-Heading 'Step 4/5 - Restoring PostgreSQL cluster & promoting onto clean timeline'
        $pgTar = Join-Path $snapDir 'postgres.tar'
        & cmd.exe /c "type `"$pgTar`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --read-only --security-opt no-new-privileges --user 0:0 -v oscar_postgres_data:/data --entrypoint sh oscar:$ver -eu -c `"find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar -C /data --no-same-owner -xf - && chown -R 999:999 /data && chmod 0700 /data`""
        if ($LASTEXITCODE -ne 0) { Fail 'Failed extracting PostgreSQL base backup.' }
        & docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --read-only --cap-drop ALL --security-opt no-new-privileges `
            --user 999:999 --entrypoint /usr/local/bin/oscar-prepare-restore `
            --volume 'oscar_postgres_data:/data' `
            "oscar-postgis:$ver" /data | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'Failed preparing PostgreSQL restore directory.' }

        Invoke-Compose @('up', '--detach', '--no-deps', '--no-build', '--pull', 'never', '--wait', '--wait-timeout', '300', 'postgres')
        $pgCid = ([string](& docker compose --project-name oscar --project-directory $ScriptRoot --env-file (Join-Path $ScriptRoot '.env') --file (Join-Path $ScriptRoot 'compose.yaml') ps --quiet postgres)).Trim()
        $pgPassFile = Join-Path $ScriptRoot 'secrets\postgres-bootstrap-password.txt'
        & cmd.exe /c "type `"$pgPassFile`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network `"container:$pgCid`" --read-only --cap-drop ALL --security-opt no-new-privileges --user 999:999 --entrypoint sh oscar-postgis:$ver -eu -c `"PGPASSWORD=`$(cat); export PGPASSWORD; for s in restore_command recovery_target recovery_target_timeline recovery_target_action; do psql -h 127.0.0.1 -p 5432 -U oscar_bootstrap -d gis -q -c 'ALTER SYSTEM RESET '`$s';'; done; psql -h 127.0.0.1 -p 5432 -U oscar_bootstrap -d gis -q -c 'CHECKPOINT; SELECT pg_reload_conf();'`""
        Invoke-Compose @('stop', 'postgres')
        Invoke-Compose @('up', '--detach', '--no-deps', '--no-build', '--pull', 'never', '--wait', '--wait-timeout', '300', 'postgres')

        Write-Heading 'Step 5/5 - Starting OSCAR application & HTTPS gateway'
        Invoke-Compose @('up', '--detach', '--no-deps', '--no-build', '--pull', 'never', '--wait', '--wait-timeout', '300', 'oscar', 'gateway')
        Write-Host "`nRESTORE COMPLETE: Snapshot $snapId is now live." -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $credsStage -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $credsIn -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ControlDirSh([string]$ShCmd, [string]$StdinText = '') {
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
            $tmpIn = Join-Path $env:TEMP "oscar-ctrl-in-$([Guid]::NewGuid().ToString('N')).tmp"
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
                return ([string](& cmd.exe /c "type `"$tmpIn`" | docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine -i --network none --user 10001:10001 -v oscar_oscar_state:/var/lib/oscar --entrypoint sh oscar:$ver -eu -c `"$ShCmd`" 2>nul"))
            }
            return ([string](& docker run --rm --label com.docker.compose.project=oscar-usb-backup --label com.docker.compose.service=usb-backup-engine --network none --user 10001:10001 -v oscar_oscar_state:/var/lib/oscar --entrypoint sh "oscar:$ver" -eu -c $ShCmd 2>$null))
        } finally { $ErrorActionPreference = $prev }
    } finally {
        if ($tmpIn) { Remove-Item -LiteralPath $tmpIn -Force -ErrorAction SilentlyContinue }
    }
}

function Get-CandidateDrivesArray($Cfg) {
    $list = @()
    $sysDrive = ($env:SystemDrive -replace ':','').ToUpperInvariant()
    $cfgDl = if ($Cfg -and $Cfg.driveLetter) { ([string]$Cfg.driveLetter -replace ':','').Trim().ToUpperInvariant() } else { '' }
    try {
        foreach ($disk in @(Get-Disk | Where-Object { -not $_.IsBoot -and -not $_.IsSystem -and ($_.BusType -eq 'USB' -or $_.Number -eq $(if ($Cfg) { $Cfg.diskNumber } else { -99 })) })) {
            $parts = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter })
            foreach ($p in $parts) {
                $dl = ([string]$p.DriveLetter).Trim().ToUpperInvariant()
                if ($dl -eq $sysDrive) { continue }
                $vol = Get-Volume -DriveLetter $dl -ErrorAction SilentlyContinue
                $sz = if ($vol -and $vol.Size) { [int64]$vol.Size } else { [int64]$disk.Size }
                $szHuman = if ($sz -ge 1000000000000) { '{0:N2} TB' -f ($sz / 1000000000000.0) } else { '{0:N1} GB' -f ($sz / 1000000000.0) }
                $list += [ordered]@{
                    device              = "${dl}:"
                    partition           = "${dl}:"
                    model               = [string]$disk.FriendlyName
                    transport           = ([string]$disk.BusType).ToLowerInvariant()
                    sizeBytes           = $sz
                    sizeHuman           = $szHuman
                    fstype              = if ($vol -and $vol.FileSystem) { ([string]$vol.FileSystem).ToLowerInvariant() } else { '' }
                    label               = if ($vol -and $vol.FileSystemLabel) { [string]$vol.FileSystemLabel } else { '' }
                    uuid                = ''
                    mountpoint          = "${dl}:\"
                    isConfiguredCarrier = ($dl -eq $cfgDl -and $cfgDl -ne '')
                }
            }
        }
    } catch {}
    return $list
}

function Write-AgentStatusJson($OverrideJob) {
    try {
        $cfg = Read-UsbConfig
        $prevRaw = Invoke-ControlDirSh 'cat /var/lib/oscar/.moduledata/usb-backup-control/status.json 2>/dev/null || true'
        $activeJob = $OverrideJob
        $cachedSnap = $null
        if (-not [string]::IsNullOrWhiteSpace($prevRaw)) {
            try {
                $prevObj = $prevRaw | ConvertFrom-Json
                if ($null -eq $activeJob -and $prevObj.PSObject.Properties['activeJob']) {
                    $activeJob = $prevObj.activeJob
                }
                if ($prevObj.PSObject.Properties['latestSnapshot']) {
                    $cachedSnap = $prevObj.latestSnapshot
                }
            } catch {}
        }

        $configured = ($null -ne $cfg)
        $mode = if ($configured) { [string]$cfg.mode } else { 'unconfigured' }
        $interval = if ($configured) { [int]$cfg.intervalMinutes } else { 15 }
        $mountPath = if ($configured) { [string]$cfg.targetPath } else { '' }
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $timerActive = ($null -ne $task -and [string]$task.State -ne 'Disabled')
        $keyPresent = Test-Path -LiteralPath (Join-Path $ScriptRoot 'secrets\backup-key.txt')

        $driveState = 'UNCONFIGURED'
        $totalBytes = [int64]0; $freeBytes = [int64]0; $usedBytes = [int64]0
        $latestSnap = $cachedSnap

        if ($configured) {
            if (Test-DriveAttached $cfg) {
                $driveState = 'ATTACHED'
                $dl = ([string]$cfg.driveLetter -replace ':','').Trim()
                if (-not [string]::IsNullOrWhiteSpace($dl)) {
                    $vol = Get-Volume -DriveLetter $dl -ErrorAction SilentlyContinue
                    if ($vol) {
                        $totalBytes = [int64]$vol.Size
                        $freeBytes = [int64]$vol.SizeRemaining
                        $usedBytes = [Math]::Max([int64]0, $totalBytes - $freeBytes)
                    }
                }
                $latestFile = Join-Path $mountPath 'OSCAR-Backup\LATEST'
                if (Test-Path -LiteralPath $latestFile) {
                    $snapId = Get-EnvFileValue $latestFile 'snapshot_id' ''
                    $epFile = Join-Path $mountPath "OSCAR-Backup\snapshots\$snapId\epoch.json"
                    if (Test-Path -LiteralPath $epFile) {
                        $latestSnap = Get-Content -LiteralPath $epFile -Raw | ConvertFrom-Json
                    }
                }
            } else {
                $diskOffline = $false
                if ([int]$cfg.diskNumber -ge 0) {
                    $d = Get-Disk -Number ([int]$cfg.diskNumber) -ErrorAction SilentlyContinue
                    if ($d -and $d.IsOffline) { $diskOffline = $true }
                }
                if ($diskOffline -or (Test-Path -LiteralPath (Join-Path $mountPath '.oscar-ejected'))) {
                    $driveState = 'SAFE_TO_UNPLUG'
                } else {
                    $driveState = 'DETACHED'
                }
            }
        }

        $statusObj = [ordered]@{
            agentActive      = $true
            hostPlatform     = 'windows'
            updatedAt        = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            configured       = $configured
            mode             = $mode
            intervalMinutes  = $interval
            mountPath        = $mountPath
            filesystem       = 'ntfs'
            fsUuid           = ''
            timerActive      = $timerActive
            driveState       = $driveState
            backupKeyPresent = $keyPresent
            driveTotalBytes  = $totalBytes
            driveFreeBytes   = $freeBytes
            backupUsedBytes  = $usedBytes
            latestSnapshot   = $latestSnap
            candidateDrives  = @(Get-CandidateDrivesArray $cfg)
            activeJob        = $activeJob
        }
        $json = $statusObj | ConvertTo-Json -Depth 6
        Invoke-ControlDirSh 'mkdir -p /var/lib/oscar/.moduledata/usb-backup-control && cat >/var/lib/oscar/.moduledata/usb-backup-control/.status.tmp && mv -f /var/lib/oscar/.moduledata/usb-backup-control/.status.tmp /var/lib/oscar/.moduledata/usb-backup-control/status.json' $json | Out-Null
    } catch {}
}

function Invoke-AgentTick([switch]$StatusOnly) {
    Assert-Administrator
    Invoke-ControlDirSh 'mkdir -p /var/lib/oscar/.moduledata/usb-backup-control && find /var/lib/oscar/.moduledata/usb-backup-control -maxdepth 1 -type f -name "escrow-*.key" -mmin +1 -delete 2>/dev/null || true' | Out-Null

    $reqRaw = Invoke-ControlDirSh 'if [ -f /var/lib/oscar/.moduledata/usb-backup-control/request.json ]; then mv -f /var/lib/oscar/.moduledata/usb-backup-control/request.json /var/lib/oscar/.moduledata/usb-backup-control/.processing.json && cat /var/lib/oscar/.moduledata/usb-backup-control/.processing.json && rm -f /var/lib/oscar/.moduledata/usb-backup-control/.processing.json; fi'
    if ([string]::IsNullOrWhiteSpace($reqRaw)) {
        if ($StatusOnly) { Write-AgentStatusJson $null }
        return
    }

    $req = $reqRaw | ConvertFrom-Json
    $act = ([string]$req.action).ToLowerInvariant()
    $reqId = [string]$req.requestId
    $reqBy = [string]$req.requestedBy
    $startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    if ($act -ceq 'export-backup-key') {
        if ($reqId -match '^[A-Za-z0-9-]{8,64}$') {
            $keyPath = Ensure-BackupKey
            $keyText = [System.IO.File]::ReadAllText($keyPath)
            Invoke-ControlDirSh "cat >/var/lib/oscar/.moduledata/usb-backup-control/.escrow.tmp && mv -f /var/lib/oscar/.moduledata/usb-backup-control/.escrow.tmp /var/lib/oscar/.moduledata/usb-backup-control/escrow-$reqId.key" $keyText | Out-Null
            Write-AgentStatusJson $null
        }
        return
    }
    if ($act -ceq 'refresh-status') {
        Write-AgentStatusJson ([ordered]@{
            requestId   = $reqId
            action      = 'refresh-status'
            state       = 'SUCCEEDED'
            startedAt   = $startedAt
            finishedAt  = $startedAt
            requestedBy = $reqBy
            message     = 'Refreshed USB drive status.'
        })
        return
    }

    Write-AgentStatusJson ([ordered]@{
        requestId   = $reqId
        action      = $act
        state       = 'RUNNING'
        startedAt   = $startedAt
        requestedBy = $reqBy
        message     = "Executing $act..."
    })

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $selfScript = Join-Path $ScriptRoot 'oscar-usb-backup.ps1'
    $subArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $selfScript)
    switch ($act) {
        'prepare-drive' {
            $dl = ([string]$req.device -replace ':','').Trim()
            $subArgs += @('prepare-drive', '-DriveLetter', $dl, '-Mode', ([string]$req.mode), '-IntervalMinutes', "$([int]$req.intervalMinutes)")
            if (-not [bool]$req.noFormat) {
                $subArgs += @('-Format', '-Confirm', ([string]$req.confirm))
            }
        }
        'set-mode' { $subArgs += @('mode', ([string]$req.mode), '-IntervalMinutes', "$([int]$req.intervalMinutes)") }
        'sync'     { $subArgs += @('sync'); if ([bool]$req.quiesce) { $subArgs += '-Quiesce' } }
        'eject'    { $subArgs += @('eject'); if ([bool]$req.noSync) { $subArgs += '-NoSync' } }
        'attach'   { $subArgs += @('attach') }
        'verify'   { $subArgs += @('verify'); if ([bool]$req.deep) { $subArgs += '-Deep' } }
    }

    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $outputText = ''
    $rc = 0
    try {
        $outputLines = & $psExe @subArgs 2>&1
        $rc = $LASTEXITCODE
        $outputText = ($outputLines | Out-String).Trim()
    } catch {
        $rc = 1
        $outputText = $_.Exception.Message
    } finally {
        $ErrorActionPreference = $prev
    }

    $finishedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $finalState = if ($rc -eq 0) { 'SUCCEEDED' } else { 'FAILED' }
    $lastLine = @($outputText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($lastLine)) { $lastLine = "Finished $act (exit $rc)." }

    Write-AgentStatusJson ([ordered]@{
        requestId   = $reqId
        action      = $act
        state       = $finalState
        startedAt   = $startedAt
        finishedAt  = $finishedAt
        requestedBy = $reqBy
        message     = [string]$lastLine
    })
}

function Invoke-AgentWatch {
    Assert-Administrator
    $lastStatusAt = [DateTime]::MinValue
    while ($true) {
        $doStatus = (((Get-Date) - $lastStatusAt).TotalSeconds -ge 15)
        try {
            Invoke-AgentTick -StatusOnly:$doStatus
            if ($doStatus) { $lastStatusAt = Get-Date }
        } catch {}
        Start-Sleep -Seconds 2
    }
}

function Invoke-InstallAgent {
    Assert-Administrator
    $agentTaskName = 'OSCAR-UsbBackupAgent'
    if ($env:OSCAR_USB_BACKUP_SKIP_TASK -ne '1') {
        if (Get-ScheduledTask -TaskName $agentTaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $agentTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $selfScript = Join-Path $ScriptRoot 'oscar-usb-backup.ps1'
        $action = New-ScheduledTaskAction -Execute $psExe -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$selfScript`" agent-watch" -WorkingDirectory $ScriptRoot
        $triggerBoot = New-ScheduledTaskTrigger -AtStartup
        $triggerKeepAlive = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -Priority 8
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $agentTaskName -Action $action -Trigger @($triggerBoot, $triggerKeepAlive) -Settings $settings -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName $agentTaskName -ErrorAction SilentlyContinue
    }
    Invoke-AgentTick -StatusOnly
    Write-Host 'Installed OSCAR Windows USB backup host control agent.' -ForegroundColor Green
}

function Show-Usage {
    Write-Host @"
Usage:
  .\oscar.bat usb-backup list-drives
  .\oscar.bat usb-backup prepare-drive -DriveLetter R [-Format -Confirm FORMAT] [-Mode continual|occasional] [-IntervalMinutes 15]
  .\oscar.bat usb-backup prepare-drive -Path D:\OSCAR-USB-Backup [-Mode continual|occasional] [-IntervalMinutes 15]
  .\oscar.bat usb-backup mode <continual|occasional|disabled> [-IntervalMinutes 15]
  .\oscar.bat usb-backup sync [-Quiesce] [-IfAttached]
  .\oscar.bat usb-backup eject [-NoSync]
  .\oscar.bat usb-backup attach
  .\oscar.bat usb-backup status
  .\oscar.bat usb-backup verify [-From PATH] [-BackupKey FILE] [-Deep]
  .\oscar.bat usb-backup restore [-From PATH] [-BackupKey FILE] [-ArchiveDir PATH] -Confirm RESTORE
  .\oscar.bat usb-backup install-agent
"@
}

switch ($Subcommand.ToLowerInvariant()) {
    'list-drives'   { Invoke-ListDrives }
    'prepare-drive' { Invoke-PrepareDrive $RemainingArgs }
    'mode'          { Invoke-Mode $RemainingArgs }
    'sync'          { Invoke-Sync $RemainingArgs }
    'eject'         { Invoke-Eject $RemainingArgs }
    'attach'        { Invoke-Attach }
    'status'        { Invoke-Status }
    'verify'        { Invoke-Verify $RemainingArgs }
    'restore'       { Invoke-Restore $RemainingArgs }
    'install-agent' { Invoke-InstallAgent }
    'agent-tick'    { Invoke-AgentTick -StatusOnly:($RemainingArgs -contains '-StatusOnly' -or $RemainingArgs -contains '--status-only') }
    'agent-watch'   { Invoke-AgentWatch }
    'help'          { Show-Usage }
    '--help'        { Show-Usage }
    '-h'            { Show-Usage }
    default         { Fail "Unknown usb-backup subcommand: $Subcommand (run .\oscar.bat usb-backup help)" }
}
