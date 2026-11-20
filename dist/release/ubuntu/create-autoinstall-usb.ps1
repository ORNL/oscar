[CmdletBinding()]
param(
    [switch]$ListDrives,
    [switch]$Help,
    [string]$IsoPath,
    [string]$OfflineBundlePath,
    [int]$DiskNumber = -1,
    [string]$Hostname = 'oscar-host',
    [string]$Username = 'oscaradmin',
    [string]$PasswordHash = '',
    [string[]]$SshKeyFile = @(),
    [string]$SeedDirectory = '',
    [string[]]$SeedFile = @(),
    [string]$ConfirmToken = '',
    [string]$RenderUserDataOnly = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Assert-NoReparsePoint([string]$CandidatePath) {
    $current = [IO.Path]::GetFullPath($CandidatePath)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to execute through a symlink or junction reparse point: $current"
            }
        }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}

$ScriptFilePath = $MyInvocation.MyCommand.Path
Assert-NoReparsePoint $ScriptFilePath
$UbuntuDir = Split-Path -Parent ([IO.Path]::GetFullPath($ScriptFilePath))
$ReleaseDir = Split-Path -Parent $UbuntuDir
$TemplateUserData = Join-Path (Join-Path $UbuntuDir 'autoinstall') 'user-data.yaml'
$TemplateMetaData = Join-Path (Join-Path $UbuntuDir 'autoinstall') 'meta-data'

function Show-Usage {
    Write-Host @'
Usage (run from an Administrator PowerShell or .\oscar.bat):
  .\oscar.bat create-autoinstall-usb                              (Interactive guided USB builder)
  .\oscar.bat create-autoinstall-usb -ListDrives                  (List safe external USB drives)
  .\oscar.bat create-autoinstall-usb `
      -IsoPath C:\Downloads\ubuntu-24.04.5-live-server-amd64.iso `
      -OfflineBundlePath C:\Downloads\oscar-3.11.0-ubuntu-x86_64-offline-full.zip `
      -DiskNumber 2 `
      -Hostname oscar-host `
      -Username oscaradmin `
      -SshKeyFile "$HOME\.ssh\id_ed25519.pub" `
      -SeedDirectory C:\oscar-seed `
      -ConfirmToken ERASE-USB

Safety guarantees:
  - Strictly blocks internal NVMe/SATA/SAS OS drives, system/boot disks, the drive
    hosting Windows or OSCAR, and any USB drive containing an OSCAR_BACKUP volume.
  - Requires ZERO third-party tools (no Rufus or 7-Zip needed): builds a native
    3-partition GPT UEFI (Secure Boot compatible) USB drive with UBUNTU_LIVE,
    CIDATA, and OSCAR_MEDIA + pre-staged seed files for the First-Boot Wizard.
'@
}

function Test-ValidHostname([string]$Value) {
    return ($Value -match '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
}

function Test-ValidLinuxUsername([string]$Value) {
    return ($Value -match '^[a-z_][a-z0-9_-]{0,30}$')
}

function Build-CustomUserData([string]$TemplatePath, [string]$HostVal, [string]$UserVal, [string]$PassHash, [string[]]$AuthorizedKeys) {
    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Missing autoinstall template: $TemplatePath"
    }
    $raw = [IO.File]::ReadAllText($TemplatePath, $Utf8NoBom) -replace "`r`n", "`n"
    $lines = $raw -split "`n"
    $outLines = New-Object System.Collections.Generic.List[string]
    $replacedHost = $false
    $replacedUser = $false
    $replacedPass = $false
    $replacedKeys = $false

    foreach ($line in $lines) {
        if (-not $replacedHost -and $line -match '^(\s*hostname:\s*).*$') {
            $outLines.Add("$($Matches[1])$HostVal")
            $replacedHost = $true
            continue
        }
        if (-not $replacedUser -and $line -match '^(\s*username:\s*).*$') {
            $outLines.Add("$($Matches[1])$UserVal")
            $replacedUser = $true
            continue
        }
        if ($PassHash -and -not $replacedPass -and $line -match '^(\s*password:\s*).*$') {
            $outLines.Add("$($Matches[1])`"$PassHash`"")
            $replacedPass = $true
            continue
        }
        if ($AuthorizedKeys.Count -gt 0 -and -not $replacedKeys -and $line -match '^\s*authorized-keys:\s*\[\]\s*$') {
            $outLines.Add('    authorized-keys:')
            foreach ($k in $AuthorizedKeys) {
                $cleanKey = $k.Trim() -replace '"', '\"'
                if ($cleanKey) {
                    $outLines.Add("      - `"$cleanKey`"")
                }
            }
            $replacedKeys = $true
            continue
        }
        $modLine = $line
        if ($UserVal -ne 'oscaradmin') {
            $modLine = $modLine.Replace('oscaradmin ALL=(ALL) NOPASSWD:ALL', "$UserVal ALL=(ALL) NOPASSWD:ALL")
            $modLine = $modLine.Replace('90-oscaradmin', "90-$UserVal")
            $modLine = $modLine.Replace('chown -R oscaradmin:oscaradmin /srv/oscar', "chown -R ${UserVal}:${UserVal} /srv/oscar")
        }
        $outLines.Add($modLine)
    }
    return (($outLines -join "`n") + "`n")
}

function Get-ProtectedDiskNumbers {
    $protected = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($d in @(Get-Disk)) {
        if ($d.IsBoot -or $d.IsSystem -or $d.BusType -ne 'USB') {
            [void]$protected.Add([int]$d.Number)
        }
    }
    $sysDriveLetter = ($env:SystemDrive -replace ':', '').Trim()
    $releaseRootLetter = ([IO.Path]::GetPathRoot($ReleaseDir) -replace '[:\\]', '').Trim()
    foreach ($dl in @($sysDriveLetter, $releaseRootLetter)) {
        if ($dl -match '^[A-Za-z]$') {
            $part = Get-Partition -DriveLetter $dl -ErrorAction SilentlyContinue
            if ($part) { [void]$protected.Add([int]$part.DiskNumber) }
        }
    }
    foreach ($vol in @(Get-Volume -ErrorAction SilentlyContinue)) {
        if ($vol.FileSystemLabel -eq 'OSCAR_BACKUP' -and $vol.DriveLetter) {
            $part = Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction SilentlyContinue
            if ($part) { [void]$protected.Add([int]$part.DiskNumber) }
        }
    }
    return @($protected)
}

function Get-CandidateUsbDisks {
    $protected = @(Get-ProtectedDiskNumbers)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($d in @(Get-Disk | Sort-Object Number)) {
        if ($protected -contains [int]$d.Number) { continue }
        if ($d.BusType -ne 'USB') { continue }
        if ($d.Size -lt 8GB) { continue }
        $hasBackupLabel = $false
        foreach ($p in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)) {
            $v = $p | Get-Volume -ErrorAction SilentlyContinue
            if ($v -and $v.FileSystemLabel -eq 'OSCAR_BACKUP') {
                $hasBackupLabel = $true
            }
        }
        if ($hasBackupLabel) { continue }
        $results.Add([pscustomobject]@{
            DiskNumber   = [int]$d.Number
            FriendlyName = [string]$d.FriendlyName
            SerialNumber = [string]$d.SerialNumber
            SizeGiB      = [Math]::Round(($d.Size / 1GB), 1)
            PartitionStyle = [string]$d.PartitionStyle
        })
    }
    return $results
}

if ($Help) {
    Show-Usage
    exit 0
}

if (-not (Test-ValidHostname $Hostname)) {
    throw "Invalid -Hostname '$Hostname' (use letters, digits, and hyphens)."
}
if (-not (Test-ValidLinuxUsername $Username)) {
    throw "Invalid Linux -Username '$Username' (use lowercase letters, digits, underscore, or hyphen)."
}

$resolvedSshKeys = New-Object System.Collections.Generic.List[string]
foreach ($kf in $SshKeyFile) {
    if (-not $kf) { continue }
    if (-not (Test-Path -LiteralPath $kf -PathType Leaf)) {
        throw "SSH public key file not found: $kf"
    }
    foreach ($line in @(Get-Content -LiteralPath $kf)) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith('#')) {
            $resolvedSshKeys.Add($trimmed)
        }
    }
}

# Offline unit-test mode: render user-data cleanly with LF endings without touching disks
if ($RenderUserDataOnly) {
    $rendered = Build-CustomUserData $TemplateUserData $Hostname $Username $PasswordHash $resolvedSshKeys.ToArray()
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($RenderUserDataOnly), $rendered, $Utf8NoBom)
    Write-Host "Rendered cloud-init autoinstall user-data to $RenderUserDataOnly"
    exit 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'create-autoinstall-usb.ps1 must run on Windows 11 (on Ubuntu, run: sudo bash oscar.sh create-autoinstall-usb).'
}

if ($ListDrives) {
    $prot = @(Get-ProtectedDiskNumbers | Sort-Object)
    Write-Host "Protected internal / OS / backup DiskNumbers (NEVER touched): $($prot -join ', ')"
    $cands = @(Get-CandidateUsbDisks)
    if ($cands.Count -eq 0) {
        Write-Host 'No candidate external USB drives (>= 8 GiB) detected.'
    } else {
        $cands | Format-Table -AutoSize
    }
    exit 0
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Administrator privileges are required to partition and format a bootable USB drive. Run .\oscar.bat from an elevated prompt.'
}

$candidates = @(Get-CandidateUsbDisks)
if ($DiskNumber -lt 0) {
    if ($candidates.Count -eq 0) {
        throw 'No safe removable USB drives (>= 8 GiB) detected. Plug in an external USB drive and try again.'
    }
    Write-Host "`nCandidate External USB Drives:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        $c = $candidates[$i]
        Write-Host ("  [{0}] Disk {1} - {2} GiB - {3} (Serial: {4})" -f ($i + 1), $c.DiskNumber, $c.SizeGiB, $c.FriendlyName, $c.SerialNumber)
    }
    $sel = Read-Host "Select USB drive [1-$($candidates.Count)]"
    $selIdx = 0
    if (-not [int]::TryParse($sel, [ref]$selIdx) -or $selIdx -lt 1 -or $selIdx -gt $candidates.Count) {
        throw 'Invalid drive selection.'
    }
    $DiskNumber = $candidates[$selIdx - 1].DiskNumber
}

$selectedCandidate = $candidates | Where-Object { $_.DiskNumber -eq $DiskNumber } | Select-Object -First 1
if (-not $selectedCandidate) {
    throw "DiskNumber $DiskNumber is either missing, internal/non-USB, smaller than 8 GiB, or protected (OS / OSCAR_BACKUP)."
}

if (-not $IsoPath) {
    $downloadsDir = Join-Path $HOME 'Downloads'
    $defaultIso = ''
    if (Test-Path -LiteralPath $downloadsDir) {
        $foundIso = Get-ChildItem -LiteralPath $downloadsDir -Filter 'ubuntu-24.04*-live-server-amd64.iso' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundIso) { $defaultIso = $foundIso.FullName }
    }
    $promptIso = if ($defaultIso) { "Path to ubuntu-24.04.x-live-server-amd64.iso [$defaultIso]" } else { 'Path to ubuntu-24.04.x-live-server-amd64.iso' }
    $replyIso = Read-Host $promptIso
    $IsoPath = if ($replyIso) { $replyIso.Trim('"') } else { $defaultIso }
}
if (-not $IsoPath -or -not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
    throw "Ubuntu 24.04 Live Server ISO not found: $IsoPath"
}
$IsoPath = [IO.Path]::GetFullPath($IsoPath)

if (-not $OfflineBundlePath -and $ConfirmToken -ne 'ERASE-USB') {
    $downloadsDir = Join-Path $HOME 'Downloads'
    $defaultBundle = ''
    foreach ($dir in @((Get-Location).Path, (Split-Path -Parent $ReleaseDir), $downloadsDir)) {
        if ($dir -and (Test-Path -LiteralPath $dir)) {
            $foundZip = Get-ChildItem -LiteralPath $dir -Filter 'oscar-*-ubuntu-x86_64-offline-full.zip' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundZip) { $defaultBundle = $foundZip.FullName; break }
        }
    }
    $promptBundle = if ($defaultBundle) { "Path to oscar-*-ubuntu-x86_64-offline-full.zip (Enter to use default, or 'skip') [$defaultBundle]" } else { 'Path to oscar-*-ubuntu-x86_64-offline-full.zip (blank to skip)' }
    $replyBundle = Read-Host $promptBundle
    if ($replyBundle -eq 'skip') {
        $OfflineBundlePath = ''
    } elseif ($replyBundle) {
        $OfflineBundlePath = $replyBundle.Trim('"')
    } else {
        $OfflineBundlePath = $defaultBundle
    }
}
if ($OfflineBundlePath) {
    if (-not (Test-Path -LiteralPath $OfflineBundlePath -PathType Leaf)) {
        throw "Ubuntu offline bundle ZIP not found: $OfflineBundlePath"
    }
    $OfflineBundlePath = [IO.Path]::GetFullPath($OfflineBundlePath)
    if ($selectedCandidate.SizeGiB -lt 14) {
        throw "Selected USB drive ($($selectedCandidate.SizeGiB) GiB) is too small to hold both Ubuntu 24.04 Live ISO and the OSCAR offline bundle (use a 16+ GiB USB drive)."
    }
}

if ($resolvedSshKeys.Count -eq 0) {
    $sshDir = Join-Path $HOME '.ssh'
    if (Test-Path -LiteralPath $sshDir) {
        foreach ($pub in @(Get-ChildItem -LiteralPath $sshDir -Filter '*.pub' -File -ErrorAction SilentlyContinue)) {
            foreach ($line in @(Get-Content -LiteralPath $pub.FullName)) {
                $trimmed = $line.Trim()
                if ($trimmed -and -not $trimmed.StartsWith('#')) { $resolvedSshKeys.Add($trimmed) }
            }
        }
    }
}

if (-not $SeedDirectory -and $SeedFile.Count -eq 0 -and $ConfirmToken -ne 'ERASE-USB') {
    $replySeed = Read-Host 'Optional seed folder (config.json, lanes.csv, site-network.env, *.pmtiles, backup-key.txt; Enter to skip)'
    if ($replySeed) { $SeedDirectory = $replySeed.Trim('"') }
}
if ($SeedDirectory -and -not (Test-Path -LiteralPath $SeedDirectory -PathType Container)) {
    throw "SeedDirectory not found: $SeedDirectory"
}
foreach ($sf in $SeedFile) {
    if ($sf -and -not (Test-Path -LiteralPath $sf -PathType Leaf)) {
        throw "SeedFile not found: $sf"
    }
}

if ($ConfirmToken -cne 'ERASE-USB') {
    Write-Host "`nWARNING: ALL DATA ON USB DISK $DiskNumber ($($selectedCandidate.SizeGiB) GiB $($selectedCandidate.FriendlyName)) WILL BE ERASED!" -ForegroundColor Yellow
    $ConfirmToken = Read-Host 'Type ERASE-USB to proceed'
    if ($ConfirmToken -cne 'ERASE-USB') {
        throw 'Cancelled (expected exact confirmation token ERASE-USB).'
    }
}

$userDataContent = Build-CustomUserData $TemplateUserData $Hostname $Username $PasswordHash $resolvedSshKeys.ToArray()
$metaDataContent = [IO.File]::ReadAllText($TemplateMetaData, $Utf8NoBom) -replace "`r`n", "`n"

$mountedIso = $null
try {
    Write-Host "==> Mounting Ubuntu 24.04 Live Server ISO ($IsoPath)..." -ForegroundColor Cyan
    $mountedIso = Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -Access ReadOnly -PassThru
    $isoVol = $mountedIso | Get-Volume
    if (-not $isoVol -or -not $isoVol.DriveLetter) {
        throw "Windows mounted $IsoPath without assigning a drive letter."
    }
    $isoRoot = "$($isoVol.DriveLetter):\"
    if (-not (Test-Path -LiteralPath (Join-Path $isoRoot 'EFI\boot\bootx64.efi'))) {
        throw "Mounted ISO at $isoRoot does not contain EFI\boot\bootx64.efi (verify it is an x86-64 Ubuntu 24.04 Live Server ISO)."
    }

    Write-Host "==> Clearing and initializing USB Disk $DiskNumber as GPT..." -ForegroundColor Cyan
    Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
    $diskObj = Get-Disk -Number $DiskNumber
    if ($diskObj.PartitionStyle -eq 'RAW') {
        Initialize-Disk -Number $DiskNumber -PartitionStyle GPT
    } else {
        Set-Disk -Number $DiskNumber -PartitionStyle GPT
    }

    Write-Host '==> Creating Partition 1 (UBUNTU_LIVE, 6 GiB FAT32), Partition 2 (CIDATA, 64 MiB FAT32), and Partition 3 (OSCAR_MEDIA, NTFS)...' -ForegroundColor Cyan
    $pLive = New-Partition -DiskNumber $DiskNumber -Size 6GB -AssignDriveLetter
    Format-Volume -Partition $pLive -FileSystem FAT32 -NewFileSystemLabel 'UBUNTU_LIVE' -Confirm:$false | Out-Null

    $pCidata = New-Partition -DiskNumber $DiskNumber -Size 64MB -AssignDriveLetter
    Format-Volume -Partition $pCidata -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Confirm:$false | Out-Null

    $pMedia = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $pMedia -FileSystem NTFS -NewFileSystemLabel 'OSCAR_MEDIA' -Confirm:$false | Out-Null

    $liveDrive = "$((Get-Partition -DiskNumber $DiskNumber -PartitionNumber $pLive.PartitionNumber).DriveLetter):\"
    $cidataDrive = "$((Get-Partition -DiskNumber $DiskNumber -PartitionNumber $pCidata.PartitionNumber).DriveLetter):\"
    $mediaDrive = "$((Get-Partition -DiskNumber $DiskNumber -PartitionNumber $pMedia.PartitionNumber).DriveLetter):\"

    Write-Host "==> Copying Ubuntu 24.04 Live Server files to $liveDrive (preserving signed UEFI Secure Boot binaries)..." -ForegroundColor Cyan
    & robocopy.exe $isoRoot $liveDrive /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed copying Ubuntu ISO files to $liveDrive (exit code $LASTEXITCODE)."
    }

    # Enhance boot\grub\grub.cfg so UEFI boot enters unattended autoinstall automatically in 5s with USB-NVMe quirks active
    $grubCfgPath = Join-Path $liveDrive 'boot\grub\grub.cfg'
    if (Test-Path -LiteralPath $grubCfgPath -PathType Leaf) {
        $quirkArgs = 'autoinstall usb-storage.quirks=0bda:9210:u,152d:0583:u,174c:2362:u,152d:0562:u,152d:0578:u usbcore.quirks=0bda:9210:k,152d:0583:k,174c:2362:k,152d:0562:k,152d:0578:k'
        $grubText = [IO.File]::ReadAllText($grubCfgPath, $Utf8NoBom) -replace "`r`n", "`n"
        $grubText = $grubText -replace 'set timeout=30', 'set timeout=5'
        $grubText = $grubText -replace '(/casper/(?:hwe-)?vmlinuz)\s+---', "`$1 $quirkArgs ---"
        Set-ItemProperty -LiteralPath $grubCfgPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        [IO.File]::WriteAllText($grubCfgPath, $grubText, $Utf8NoBom)
    }

    Write-Host "==> Writing cloud-init autoinstall profile to $cidataDrive (CIDATA)..." -ForegroundColor Cyan
    [IO.File]::WriteAllText((Join-Path $cidataDrive 'user-data'), $userDataContent, $Utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $cidataDrive 'meta-data'), $metaDataContent, $Utf8NoBom)

    $seedOutDir = Join-Path $mediaDrive 'seed'
    New-Item -ItemType Directory -Force -Path $seedOutDir | Out-Null

    if ($OfflineBundlePath) {
        $bundleLeaf = Split-Path -Leaf $OfflineBundlePath
        $destBundle = Join-Path $mediaDrive $bundleLeaf
        $destShaFile = "$destBundle.sha256"
        Write-Host "==> Copying $bundleLeaf to $mediaDrive (OSCAR_MEDIA) and verifying SHA-256..." -ForegroundColor Cyan
        Copy-Item -LiteralPath $OfflineBundlePath -Destination $destBundle -Force
        $expectedSha = ''
        if (Test-Path -LiteralPath "$OfflineBundlePath.sha256" -PathType Leaf) {
            $shaLine = (Get-Content -LiteralPath "$OfflineBundlePath.sha256" | Select-Object -First 1).Trim()
            $expectedSha = ($shaLine -split '\s+')[0].ToLowerInvariant()
        }
        $actualUsbSha = (Get-FileHash -LiteralPath $destBundle -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expectedSha -and $actualUsbSha -cne $expectedSha) {
            throw "SHA-256 mismatch on USB copy ($destBundle): expected $expectedSha, got $actualUsbSha"
        }
        [IO.File]::WriteAllText($destShaFile, "$actualUsbSha *$bundleLeaf`n", $Utf8NoBom)
    }

    if ($SeedDirectory) {
        Copy-Item -Path (Join-Path $SeedDirectory '*') -Destination $seedOutDir -Recurse -Force
    }
    foreach ($sf in $SeedFile) {
        if ($sf) {
            Copy-Item -LiteralPath $sf -Destination (Join-Path $seedOutDir (Split-Path -Leaf $sf)) -Force
        }
    }

    $readmeText = @"
OSCAR Bare-Metal Ubuntu Server 24.04 LTS Offline Autoinstall USB
================================================================
Generated UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Target Hostname: $Hostname
Admin Username:  $Username

How to Install on Bare-Metal Server / Laptop:
  1. Insert this USB drive into the target UEFI x86-64 machine (no internet needed).
  2. Power on and select this USB drive from the UEFI One-Time Boot Menu.
  3. Ubuntu Server 24.04 LTS installs automatically onto the internal NVMe/SSD
     (100% LVM capacity, USB drives excluded, USB-NVMe stability quirks enabled)
     and unpacks OSCAR into /srv/oscar/.
  4. Remove this USB drive when prompted at the end of installation and press Enter.
  5. Log in as '$Username' - the interactive OSCAR First-Boot Provisioning Wizard
     launches automatically (or run: sudo oscar-wizard).
"@
    [IO.File]::WriteAllText((Join-Path $mediaDrive 'README-BARE-METAL-INSTALL.txt'), ($readmeText -replace "`r`n", "`n"), $Utf8NoBom)

    foreach ($dl in @($liveDrive[0], $cidataDrive[0], $mediaDrive[0])) {
        Write-VolumeCache -DriveLetter $dl -ErrorAction SilentlyContinue
    }
    Write-Host "`nSUCCESS: OSCAR Bare-Metal Autoinstall USB ready on Disk $DiskNumber ($($selectedCandidate.FriendlyName)). Safe to eject and boot!" -ForegroundColor Green
} finally {
    if ($mountedIso) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
}
