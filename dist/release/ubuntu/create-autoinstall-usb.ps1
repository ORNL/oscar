[CmdletBinding()]
param(
    [switch]$Gui,
    [switch]$Tui,
    [switch]$ListDrives,
    [switch]$Help,
    [string]$IsoPath,
    [string]$OfflineBundlePath,
    [int]$DiskNumber = -1,
    [string]$Hostname = 'oscar-host',
    [string]$Username = 'oscaradmin',
    [string]$PasswordHash = '',
    [string]$PasswordFile = '',
    [string]$LuksPassphraseFile = '',
    [switch]$RequireSudoPassword,
    [switch]$SshKeysOnly,
    [string[]]$SshKeyFile = @(),
    [string]$OscarAdminPassword = '',
    [string]$OscarAdminPasswordFile = '',
    [string]$OscarAdminPasswordHash = '',
    [string]$LanesFile = '',
    [switch]$AutoInitOscar,
    [string]$SeedDirectory = '',
    [string[]]$SeedFile = @(),
    [string]$ConfirmToken = '',
    [string]$RenderUserDataOnly = '',
    [string]$TestOscarPbkdf2Only = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

if (-not ('OscarSha512Crypt' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;
using System.Text;

public static class OscarSha512Crypt {
    private const string B64 = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

    private static byte[] HashConcat(params byte[][] parts) {
        int len = 0;
        for (int i = 0; i < parts.Length; i++) len += parts[i].Length;
        byte[] buf = new byte[len];
        int off = 0;
        for (int i = 0; i < parts.Length; i++) {
            if (parts[i].Length > 0) {
                Buffer.BlockCopy(parts[i], 0, buf, off, parts[i].Length);
                off += parts[i].Length;
            }
        }
        using (SHA512 sha = SHA512.Create()) {
            return sha.ComputeHash(buf);
        }
    }

    private static void B64From24Bit(StringBuilder sb, int b2, int b1, int b0, int n) {
        int w = (b2 << 16) | (b1 << 8) | b0;
        for (int i = 0; i < n; i++) {
            sb.Append(B64[w & 0x3f]);
            w >>= 6;
        }
    }

    public static string Crypt(string password, string salt) {
        if (string.IsNullOrEmpty(salt)) {
            byte[] rnd = new byte[16];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) {
                rng.GetBytes(rnd);
            }
            StringBuilder ssb = new StringBuilder(16);
            for (int i = 0; i < 16; i++) ssb.Append(B64[rnd[i] & 0x3f]);
            salt = ssb.ToString();
        }
        if (salt.Length > 16) salt = salt.Substring(0, 16);
        byte[] key = Encoding.UTF8.GetBytes(password);
        byte[] slt = Encoding.ASCII.GetBytes(salt);
        int keyLen = key.Length;
        int saltLen = slt.Length;

        byte[] alt = HashConcat(key, slt, key);
        using (SHA512 shaA = SHA512.Create()) {
            shaA.TransformBlock(key, 0, keyLen, null, 0);
            shaA.TransformBlock(slt, 0, saltLen, null, 0);
            int cnt = keyLen;
            while (cnt > 64) { shaA.TransformBlock(alt, 0, 64, null, 0); cnt -= 64; }
            if (cnt > 0) shaA.TransformBlock(alt, 0, cnt, null, 0);
            cnt = keyLen;
            while (cnt > 0) {
                if ((cnt & 1) != 0) shaA.TransformBlock(alt, 0, 64, null, 0);
                else shaA.TransformBlock(key, 0, keyLen, null, 0);
                cnt >>= 1;
            }
            shaA.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            alt = shaA.Hash;
        }

        byte[] dp;
        using (SHA512 shaDP = SHA512.Create()) {
            for (int i = 0; i < keyLen; i++) shaDP.TransformBlock(key, 0, keyLen, null, 0);
            shaDP.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            dp = shaDP.Hash;
        }
        byte[] pBytes = new byte[keyLen];
        int pOff = 0;
        while (keyLen - pOff >= 64) { Buffer.BlockCopy(dp, 0, pBytes, pOff, 64); pOff += 64; }
        if (keyLen - pOff > 0) Buffer.BlockCopy(dp, 0, pBytes, pOff, keyLen - pOff);

        byte[] ds;
        using (SHA512 shaDS = SHA512.Create()) {
            int dsCnt = 16 + alt[0];
            for (int i = 0; i < dsCnt; i++) shaDS.TransformBlock(slt, 0, saltLen, null, 0);
            shaDS.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            ds = shaDS.Hash;
        }
        byte[] sBytes = new byte[saltLen];
        int sOff = 0;
        while (saltLen - sOff >= 64) { Buffer.BlockCopy(ds, 0, sBytes, sOff, 64); sOff += 64; }
        if (saltLen - sOff > 0) Buffer.BlockCopy(ds, 0, sBytes, sOff, saltLen - sOff);

        byte[] cur = alt;
        for (int r = 0; r < 5000; r++) {
            using (SHA512 shaC = SHA512.Create()) {
                if ((r & 1) != 0) shaC.TransformBlock(pBytes, 0, keyLen, null, 0);
                else shaC.TransformBlock(cur, 0, 64, null, 0);
                if (r % 3 != 0) shaC.TransformBlock(sBytes, 0, saltLen, null, 0);
                if (r % 7 != 0) shaC.TransformBlock(pBytes, 0, keyLen, null, 0);
                if ((r & 1) != 0) shaC.TransformBlock(cur, 0, 64, null, 0);
                else shaC.TransformBlock(pBytes, 0, keyLen, null, 0);
                shaC.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
                cur = shaC.Hash;
            }
        }

        StringBuilder outSb = new StringBuilder(120);
        outSb.Append("$6$").Append(salt).Append("$");
        B64From24Bit(outSb, cur[0], cur[21], cur[42], 4);
        B64From24Bit(outSb, cur[22], cur[43], cur[1], 4);
        B64From24Bit(outSb, cur[44], cur[2], cur[23], 4);
        B64From24Bit(outSb, cur[3], cur[24], cur[45], 4);
        B64From24Bit(outSb, cur[25], cur[46], cur[4], 4);
        B64From24Bit(outSb, cur[47], cur[5], cur[26], 4);
        B64From24Bit(outSb, cur[6], cur[27], cur[48], 4);
        B64From24Bit(outSb, cur[28], cur[49], cur[7], 4);
        B64From24Bit(outSb, cur[50], cur[8], cur[29], 4);
        B64From24Bit(outSb, cur[9], cur[30], cur[51], 4);
        B64From24Bit(outSb, cur[31], cur[52], cur[10], 4);
        B64From24Bit(outSb, cur[53], cur[11], cur[32], 4);
        B64From24Bit(outSb, cur[12], cur[33], cur[54], 4);
        B64From24Bit(outSb, cur[34], cur[55], cur[13], 4);
        B64From24Bit(outSb, cur[56], cur[14], cur[35], 4);
        B64From24Bit(outSb, cur[15], cur[36], cur[57], 4);
        B64From24Bit(outSb, cur[37], cur[58], cur[16], 4);
        B64From24Bit(outSb, cur[59], cur[17], cur[38], 4);
        B64From24Bit(outSb, cur[18], cur[39], cur[60], 4);
        B64From24Bit(outSb, cur[40], cur[61], cur[19], 4);
        B64From24Bit(outSb, cur[62], cur[20], cur[41], 4);
        B64From24Bit(outSb, 0, 0, cur[63], 2);
        return outSb.ToString();
    }

    public static string Pbkdf2Credential(string password) {
        byte[] salt = new byte[16];
        using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) {
            rng.GetBytes(salt);
        }
        byte[] pwBytes = Encoding.UTF8.GetBytes(password);
        byte[] dk;
        using (Rfc2898DeriveBytes kdf = new Rfc2898DeriveBytes(pwBytes, salt, 65536)) {
            dk = kdf.GetBytes(16);
        }
        return "# PBKDF2_PREENCODED:PBKDF2WithHmacSHA1:16:" + Convert.ToBase64String(salt) + ":" + Convert.ToBase64String(dk);
    }
}
'@
}

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
Usage (run from create-autoinstall-usb.bat, Administrator PowerShell, or .\oscar.bat):
  .\create-autoinstall-usb.bat                                    (Desktop GUI window with UAC prompt)
  .\create-autoinstall-usb.bat -Tui                               (Interactive terminal wizard / TUI)
  .\create-autoinstall-usb.bat -ListDrives                        (List safe external USB drives)
  .\create-autoinstall-usb.ps1 `
      -IsoPath C:\Downloads\ubuntu-24.04.5-live-server-amd64.iso `
      -OfflineBundlePath C:\Downloads\oscar-3.11.9-ubuntu-x86_64-offline-full.zip `
      -DiskNumber 2 `
      -Hostname oscar-host `
      -Username oscaradmin `
      -PasswordFile C:\oscar-seed\admin-password.txt `
      -LuksPassphraseFile C:\oscar-seed\luks-passphrase.txt `
      -RequireSudoPassword `
      -SshKeyFile "$HOME\.ssh\id_ed25519.pub" -SshKeysOnly `
      -OscarAdminPasswordFile C:\oscar-seed\oscar-web-admin-password.txt `
      -LanesFile C:\oscar-seed\lanes.csv `
      -AutoInitOscar `
      -SeedDirectory C:\oscar-seed `
      -ConfirmToken ERASE-USB

Modes:
  -Gui           Open the native Windows desktop GUI (default via create-autoinstall-usb.bat).
  -Tui           Run the step-by-step interactive terminal wizard (default in PowerShell consoles).
  CLI flags      Run 100% non-interactively for automated staging.

Safety guarantees:
  - Strictly blocks internal NVMe/SATA/SAS OS drives, system/boot disks, the drive
    hosting Windows or OSCAR, and any USB drive containing an OSCAR_BACKUP volume.
  - Requires ZERO third-party tools (no Rufus, OpenSSL, or 7-Zip needed): hashes Linux
    SHA-512 ($6$) passwords natively and builds a 3-partition GPT UEFI (Secure Boot
    compatible) USB drive with UBUNTU_LIVE, CIDATA, and OSCAR_MEDIA + verified SHA-256.
'@
}

function Test-ValidHostname([string]$Value) {
    return ($Value -match '^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
}

function Test-ValidLinuxUsername([string]$Value) {
    return ($Value -match '^[a-z_][a-z0-9_-]{0,30}$')
}

function ConvertFrom-SecureStringPlain([System.Security.SecureString]$Secure) {
    if (-not $Secure) { return '' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function ConvertTo-JsonEscapedScalar([string]$Val) {
    $escaped = $Val.Replace('\', '\\').Replace('"', '\"')
    return "`"$escaped`""
}

function Find-DefaultFile([string]$FilterPattern) {
    $downloadsDir = Join-Path $HOME 'Downloads'
    $searchDirs = @(
        (Get-Location).Path,
        $UbuntuDir,
        $ReleaseDir,
        (Split-Path -Parent $ReleaseDir),
        $downloadsDir
    )
    foreach ($dir in $searchDirs) {
        if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
            $found = Get-ChildItem -LiteralPath $dir -Filter $FilterPattern -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
    return ''
}

function Read-SshKeysFromFiles([string[]]$KeyPaths) {
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($kf in $KeyPaths) {
        if (-not $kf) { continue }
        if (-not (Test-Path -LiteralPath $kf -PathType Leaf)) {
            throw "SSH public key file not found: $kf"
        }
        foreach ($line in @(Get-Content -LiteralPath $kf)) {
            $trimmed = $line.Trim()
            if ($trimmed -and -not $trimmed.StartsWith('#')) {
                $keys.Add($trimmed)
            }
        }
    }
    return ,([string[]]$keys.ToArray())
}

function Build-CustomUserData([string]$TemplatePath, [string]$HostVal, [string]$UserVal, [string]$PassHash, [string]$LuksPass, [bool]$ReqSudoPw, [bool]$KeysOnly, [string[]]$AuthorizedKeys) {
    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Missing autoinstall template: $TemplatePath"
    }
    $raw = [IO.File]::ReadAllText($TemplatePath, $Utf8NoBom) -replace "`r`n", "`n"
    if ($KeysOnly) {
        $raw = $raw.Replace('allow-pw: true', 'allow-pw: false')
        $raw = $raw.Replace(
            'PermitRootLogin no\nX11Forwarding no\nMaxAuthTries 4\n',
            'PermitRootLogin no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nX11Forwarding no\nMaxAuthTries 4\n')
    }
    if ($LuksPass) {
        $luksLiteral = ConvertTo-JsonEscapedScalar $LuksPass
        $raw = $raw.Replace(
            "`"sizing-policy`": `"all`",`n          `"match`": {`"path`": target_disk},",
            "`"sizing-policy`": `"all`",`n          `"password`": $luksLiteral,`n          `"match`": {`"path`": target_disk},")
        $raw = $raw.Replace(
            "    layout:`n      name: lvm`n      sizing-policy: all",
            "    layout:`n      name: lvm`n      sizing-policy: all`n      password: $luksLiteral")
    }
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
        if ($ReqSudoPw -and $line.Contains('oscaradmin ALL=(ALL) NOPASSWD:ALL')) {
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
            DiskNumber     = [int]$d.Number
            FriendlyName   = [string]$d.FriendlyName
            SerialNumber   = [string]$d.SerialNumber
            SizeGiB        = [Math]::Round(($d.Size / 1GB), 1)
            PartitionStyle = [string]$d.PartitionStyle
        })
    }
    return $results
}

function Invoke-BuildAutoinstallUsb(
    [int]$TargetDiskNumber,
    [string]$UbuntuIso,
    [string]$BundleZip,
    [string]$HostVal,
    [string]$UserVal,
    [string]$PassHash,
    [string]$LuksPass,
    [bool]$ReqSudoPw,
    [bool]$KeysOnly,
    [string[]]$AuthorizedKeys,
    [string]$OscarWebPassHash,
    [string]$PreconfiguredLanesFile,
    [bool]$AutoInitFirstBoot,
    [string]$SeedDir,
    [string[]]$ExtraSeedFiles,
    [scriptblock]$Logger
) {
    $emit = {
        param([string]$Msg, [int]$Pct)
        if ($Logger) { & $Logger $Msg $Pct }
        else { Write-Host "==> $Msg" -ForegroundColor Cyan }
    }

    if (-not (Test-ValidHostname $HostVal)) {
        throw "Invalid Hostname '$HostVal' (use letters, digits, and hyphens)."
    }
    if (-not (Test-ValidLinuxUsername $UserVal)) {
        throw "Invalid Linux Username '$UserVal' (use lowercase letters, digits, underscore, or hyphen)."
    }
    if (-not $UbuntuIso -or -not (Test-Path -LiteralPath $UbuntuIso -PathType Leaf)) {
        throw "Ubuntu 24.04 Live Server ISO not found: $UbuntuIso"
    }
    $UbuntuIso = [IO.Path]::GetFullPath($UbuntuIso)

    $candidates = @(Get-CandidateUsbDisks)
    $selectedCandidate = $candidates | Where-Object { $_.DiskNumber -eq $TargetDiskNumber } | Select-Object -First 1
    if (-not $selectedCandidate) {
        throw "DiskNumber $TargetDiskNumber is missing, internal/non-USB, smaller than 8 GiB, or protected (OS / OSCAR_BACKUP)."
    }

    if ($BundleZip) {
        if (-not (Test-Path -LiteralPath $BundleZip -PathType Leaf)) {
            throw "Ubuntu offline bundle ZIP not found: $BundleZip"
        }
        $BundleZip = [IO.Path]::GetFullPath($BundleZip)
        if ($selectedCandidate.SizeGiB -lt 14) {
            throw "Selected USB drive ($($selectedCandidate.SizeGiB) GiB) is too small to hold both Ubuntu 24.04 Live ISO and the OSCAR offline bundle (use a 16+ GiB USB drive)."
        }
    }
    if ($LuksPass -and $LuksPass.Length -lt 12) {
        throw 'LUKS2 full-disk encryption passphrase must contain at least 12 characters.'
    }
    if ($KeysOnly -and $AuthorizedKeys.Count -eq 0) {
        throw 'SSH keys only mode requires at least one SSH public key so SSH access is not locked out.'
    }
    if ($SeedDir -and -not (Test-Path -LiteralPath $SeedDir -PathType Container)) {
        throw "Seed directory not found: $SeedDir"
    }
    if ($PreconfiguredLanesFile) {
        if (-not (Test-Path -LiteralPath $PreconfiguredLanesFile -PathType Leaf)) {
            throw "Pre-configured lanes file not found: $PreconfiguredLanesFile"
        }
        $ext = ([IO.Path]::GetExtension($PreconfiguredLanesFile)).ToLowerInvariant()
        if ($ext -ne '.csv' -and $ext -ne '.json') {
            throw "-LanesFile must be a .csv lane spreadsheet or .json SensorHub/OSCAR configuration: $PreconfiguredLanesFile"
        }
    }
    if ($AutoInitFirstBoot) {
        if (-not $BundleZip) {
            throw '-AutoInitOscar requires -OfflineBundlePath (oscar-*-ubuntu-x86_64-offline-full.zip).'
        }
        if (-not $OscarWebPassHash) {
            throw '-AutoInitOscar requires an initial OSCAR Web admin password (-OscarAdminPasswordFile or GUI/TUI entry).'
        }
    }
    foreach ($sf in $ExtraSeedFiles) {
        if ($sf -and -not (Test-Path -LiteralPath $sf -PathType Leaf)) {
            throw "Seed file not found: $sf"
        }
    }

    & $emit "Rendering cloud-init autoinstall profile for '$HostVal' (user '$UserVal')..." 5
    $userDataContent = Build-CustomUserData $TemplateUserData $HostVal $UserVal $PassHash $LuksPass $ReqSudoPw $KeysOnly $AuthorizedKeys
    $metaDataContent = [IO.File]::ReadAllText($TemplateMetaData, $Utf8NoBom) -replace "`r`n", "`n"

    $mountedIso = $null
    try {
        & $emit "Mounting Ubuntu 24.04 Live Server ISO ($UbuntuIso)..." 10
        $mountedIso = Mount-DiskImage -ImagePath $UbuntuIso -StorageType ISO -Access ReadOnly -PassThru
        $isoVol = $mountedIso | Get-Volume
        if (-not $isoVol -or -not $isoVol.DriveLetter) {
            throw "Windows mounted $UbuntuIso without assigning a drive letter."
        }
        $isoRoot = "$($isoVol.DriveLetter):\"
        if (-not (Test-Path -LiteralPath (Join-Path $isoRoot 'EFI\boot\bootx64.efi'))) {
            throw "Mounted ISO at $isoRoot does not contain EFI\boot\bootx64.efi (verify it is an x86-64 Ubuntu 24.04 Live Server ISO)."
        }

        & $emit "Clearing and initializing USB Disk $TargetDiskNumber ($($selectedCandidate.SizeGiB) GiB $($selectedCandidate.FriendlyName)) as GPT..." 18
        Clear-Disk -Number $TargetDiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
        $diskObj = Get-Disk -Number $TargetDiskNumber
        if ($diskObj.PartitionStyle -eq 'RAW') {
            Initialize-Disk -Number $TargetDiskNumber -PartitionStyle GPT
        } else {
            Set-Disk -Number $TargetDiskNumber -PartitionStyle GPT
        }

        & $emit 'Creating UBUNTU_LIVE (6 GiB FAT32), CIDATA (64 MiB FAT32), and OSCAR_MEDIA (NTFS) partitions...' 28
        $pLive = New-Partition -DiskNumber $TargetDiskNumber -Size 6GB -AssignDriveLetter
        Format-Volume -Partition $pLive -FileSystem FAT32 -NewFileSystemLabel 'UBUNTU_LIVE' -Confirm:$false | Out-Null

        $pCidata = New-Partition -DiskNumber $TargetDiskNumber -Size 64MB -AssignDriveLetter
        Format-Volume -Partition $pCidata -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Confirm:$false | Out-Null

        $pMedia = New-Partition -DiskNumber $TargetDiskNumber -UseMaximumSize -AssignDriveLetter
        Format-Volume -Partition $pMedia -FileSystem NTFS -NewFileSystemLabel 'OSCAR_MEDIA' -Confirm:$false | Out-Null

        $liveDrive = "$((Get-Partition -DiskNumber $TargetDiskNumber -PartitionNumber $pLive.PartitionNumber).DriveLetter):\"
        $cidataDrive = "$((Get-Partition -DiskNumber $TargetDiskNumber -PartitionNumber $pCidata.PartitionNumber).DriveLetter):\"
        $mediaDrive = "$((Get-Partition -DiskNumber $TargetDiskNumber -PartitionNumber $pMedia.PartitionNumber).DriveLetter):\"

        & $emit "Copying Ubuntu 24.04 Live Server files to $liveDrive (preserving signed UEFI Secure Boot binaries)..." 42
        & robocopy.exe $isoRoot $liveDrive /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "robocopy failed copying Ubuntu ISO files to $liveDrive (exit code $LASTEXITCODE)."
        }

        $grubCfgPath = Join-Path $liveDrive 'boot\grub\grub.cfg'
        if (Test-Path -LiteralPath $grubCfgPath -PathType Leaf) {
            $quirkArgs = 'autoinstall usb-storage.quirks=0bda:9210:u,152d:0583:u,174c:2362:u,152d:0562:u,152d:0578:u usbcore.quirks=0bda:9210:k,152d:0583:k,174c:2362:k,152d:0562:k,152d:0578:k'
            $grubText = [IO.File]::ReadAllText($grubCfgPath, $Utf8NoBom) -replace "`r`n", "`n"
            $grubText = $grubText -replace 'set timeout=30', 'set timeout=5'
            $grubText = $grubText -replace '(/casper/(?:hwe-)?vmlinuz)\s+---', "`$1 $quirkArgs ---"
            Set-ItemProperty -LiteralPath $grubCfgPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            [IO.File]::WriteAllText($grubCfgPath, $grubText, $Utf8NoBom)
        }

        & $emit "Writing cloud-init autoinstall profile to $cidataDrive (CIDATA)..." 68
        [IO.File]::WriteAllText((Join-Path $cidataDrive 'user-data'), $userDataContent, $Utf8NoBom)
        [IO.File]::WriteAllText((Join-Path $cidataDrive 'meta-data'), $metaDataContent, $Utf8NoBom)

        $seedOutDir = Join-Path $mediaDrive 'seed'
        New-Item -ItemType Directory -Force -Path $seedOutDir | Out-Null

        if ($BundleZip) {
            $bundleLeaf = Split-Path -Leaf $BundleZip
            $destBundle = Join-Path $mediaDrive $bundleLeaf
            $destShaFile = "$destBundle.sha256"
            & $emit "Copying $bundleLeaf to $mediaDrive (OSCAR_MEDIA) and verifying SHA-256..." 78
            Copy-Item -LiteralPath $BundleZip -Destination $destBundle -Force
            $expectedSha = ''
            if (Test-Path -LiteralPath "$BundleZip.sha256" -PathType Leaf) {
                $shaLine = (Get-Content -LiteralPath "$BundleZip.sha256" | Select-Object -First 1).Trim()
                $expectedSha = ($shaLine -split '\s+')[0].ToLowerInvariant()
            }
            $actualUsbSha = (Get-FileHash -LiteralPath $destBundle -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($expectedSha -and $actualUsbSha -cne $expectedSha) {
                throw "SHA-256 mismatch on USB copy ($destBundle): expected $expectedSha, got $actualUsbSha"
            }
            [IO.File]::WriteAllText($destShaFile, "$actualUsbSha *$bundleLeaf`n", $Utf8NoBom)
            $bundleParentDir = Split-Path -Parent $BundleZip
            foreach ($searchDir in @($bundleParentDir, (Join-Path (Join-Path $ReleaseDir 'documentation') 'operator-manual'))) {
                if ($searchDir -and (Test-Path -LiteralPath $searchDir -PathType Container)) {
                    Get-ChildItem -LiteralPath $searchDir -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like 'OSCAR-*-Administrator-Operator-Manual-*.pdf' -or $_.Name -like 'OSCAR-*-SHA256SUMS.txt' } |
                        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $mediaDrive $_.Name) -Force }
                }
            }
        }

        if ($SeedDir) {
            & $emit "Staging seed directory ($SeedDir) onto OSCAR_MEDIA\seed..." 92
            Copy-Item -Path (Join-Path $SeedDir '*') -Destination $seedOutDir -Recurse -Force
        }
        foreach ($sf in $ExtraSeedFiles) {
            if ($sf) {
                Copy-Item -LiteralPath $sf -Destination (Join-Path $seedOutDir (Split-Path -Leaf $sf)) -Force
            }
        }
        if ($PreconfiguredLanesFile) {
            & $emit "Staging pre-configured lanes ($(Split-Path -Leaf $PreconfiguredLanesFile)) onto OSCAR_MEDIA\seed..." 94
            Copy-Item -LiteralPath $PreconfiguredLanesFile -Destination (Join-Path $seedOutDir (Split-Path -Leaf $PreconfiguredLanesFile)) -Force
        }
        if ($OscarWebPassHash) {
            [IO.File]::WriteAllText((Join-Path $seedOutDir 'oscar-admin-password.txt'), "$OscarWebPassHash`n", $Utf8NoBom)
        }
        if ($AutoInitFirstBoot) {
            $autoEnvText = "AUTO_INIT_OSCAR=true`nOSCAR_HOSTNAME=$HostVal`nOSCAR_HTTPS_PORT=443`n"
            [IO.File]::WriteAllText((Join-Path $seedOutDir 'auto-provision.env'), $autoEnvText, $Utf8NoBom)
        }

        $readmeText = @"
OSCAR Bare-Metal Ubuntu Server 24.04 LTS Offline Autoinstall USB
================================================================
Generated UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Target Hostname: $HostVal
Admin Username:  $UserVal

How to Install on Bare-Metal Server / Laptop:
  1. Insert this USB drive into the target UEFI x86-64 machine (no internet needed).
  2. Power on and select this USB drive from the UEFI One-Time Boot Menu.
  3. Ubuntu Server 24.04 LTS installs automatically onto the internal NVMe/SSD
     (100% LVM capacity, USB drives excluded, USB-NVMe stability quirks enabled)
     and unpacks OSCAR into /srv/oscar/.
  4. Remove this USB drive when prompted at the end of installation and press Enter.
  5. Log in as '$UserVal' - the interactive OSCAR First-Boot Provisioning Wizard
     launches automatically (or run: sudo oscar-wizard), including optional
     Safe Bench / DR Clone Isolation when testing a backup while a live portal runs.

Hardware Power Tip for 1-4 TB M.2 NVMe USB Backup Enclosures:
  High-capacity PCIe NVMe USB enclosures draw 6-8W inrush at spin-up. Connect them
  via a mains-powered USB 3.2 Gen 2 hub/dock or a dedicated rear/15W USB-C port
  rather than a 4.5W laptop USB-A port or a shared dual USB-C port next to another
  USB-C dongle.
"@
        [IO.File]::WriteAllText((Join-Path $mediaDrive 'README-BARE-METAL-INSTALL.txt'), ($readmeText -replace "`r`n", "`n"), $Utf8NoBom)

        & $emit 'Flushing volume caches to USB media...' 97
        foreach ($dl in @($liveDrive[0], $cidataDrive[0], $mediaDrive[0])) {
            Write-VolumeCache -DriveLetter $dl -ErrorAction SilentlyContinue
        }
        & $emit "SUCCESS: OSCAR Bare-Metal Autoinstall USB ready on Disk $TargetDiskNumber ($($selectedCandidate.FriendlyName)). Safe to eject and boot!" 100
    } finally {
        if ($mountedIso) {
            Dismount-DiskImage -ImagePath $UbuntuIso -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Show-AutoinstallUsbGui([string]$InitialIso, [string]$InitialBundle, [string]$InitialHost, [string]$InitialUser, [string]$InitialLanesFile, [string]$InitialSeedDir) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $defaultIso = if ($InitialIso) { $InitialIso } else { Find-DefaultFile 'ubuntu-24.04*-live-server-amd64.iso' }
    $defaultBundle = if ($InitialBundle) { $InitialBundle } else { Find-DefaultFile 'oscar-*-ubuntu-x86_64-offline-full.zip' }
    $defaultPubKey = ''
    $sshDir = Join-Path $HOME '.ssh'
    if (Test-Path -LiteralPath $sshDir -PathType Container) {
        $foundPub = Get-ChildItem -LiteralPath $sshDir -Filter '*.pub' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundPub) { $defaultPubKey = $foundPub.FullName }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'OSCAR Bare-Metal Ubuntu 24.04 Offline Autoinstall USB Creator'
    $form.ClientSize = New-Object System.Drawing.Size(760, 810)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblBanner = New-Object System.Windows.Forms.Label
    $lblBanner.Text = 'Build a UEFI Secure-Boot Ubuntu Server 24.04 LTS + Air-Gapped OSCAR Autoinstall USB Drive'
    $lblBanner.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
    $lblBanner.Location = New-Object System.Drawing.Point(16, 12)
    $lblBanner.Size = New-Object System.Drawing.Size(728, 24)
    $form.Controls.Add($lblBanner)

    # 1. USB Drive Selection
    $lblUsb = New-Object System.Windows.Forms.Label
    $lblUsb.Text = '1. Removable USB Drive (16+ GiB recommended; internal OS & OSCAR_BACKUP drives are hidden):'
    $lblUsb.Location = New-Object System.Drawing.Point(16, 42)
    $lblUsb.Size = New-Object System.Drawing.Size(620, 20)
    $form.Controls.Add($lblUsb)

    $cmbUsb = New-Object System.Windows.Forms.ComboBox
    $cmbUsb.DropDownStyle = 'DropDownList'
    $cmbUsb.Location = New-Object System.Drawing.Point(16, 64)
    $cmbUsb.Size = New-Object System.Drawing.Size(610, 26)
    $form.Controls.Add($cmbUsb)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = 'Refresh Drives'
    $btnRefresh.Location = New-Object System.Drawing.Point(634, 63)
    $btnRefresh.Size = New-Object System.Drawing.Size(110, 27)
    $form.Controls.Add($btnRefresh)

    # 2. Source Files
    $lblIso = New-Object System.Windows.Forms.Label
    $lblIso.Text = '2. Ubuntu Server 24.04 Live ISO (ubuntu-24.04.x-live-server-amd64.iso):'
    $lblIso.Location = New-Object System.Drawing.Point(16, 98)
    $lblIso.Size = New-Object System.Drawing.Size(610, 20)
    $form.Controls.Add($lblIso)

    $txtIso = New-Object System.Windows.Forms.TextBox
    $txtIso.Text = $defaultIso
    $txtIso.Location = New-Object System.Drawing.Point(16, 120)
    $txtIso.Size = New-Object System.Drawing.Size(610, 24)
    $form.Controls.Add($txtIso)

    $btnIso = New-Object System.Windows.Forms.Button
    $btnIso.Text = 'Browse...'
    $btnIso.Location = New-Object System.Drawing.Point(634, 118)
    $btnIso.Size = New-Object System.Drawing.Size(110, 26)
    $btnIso.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Select Ubuntu 24.04 Live Server ISO'
        $dlg.Filter = 'Ubuntu Live Server ISO (*.iso)|*.iso|All Files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq 'OK') { $txtIso.Text = $dlg.FileName }
    })
    $form.Controls.Add($btnIso)

    $lblBundle = New-Object System.Windows.Forms.Label
    $lblBundle.Text = '3. OSCAR Ubuntu Offline Full Archive (oscar-*-ubuntu-x86_64-offline-full.zip):'
    $lblBundle.Location = New-Object System.Drawing.Point(16, 152)
    $lblBundle.Size = New-Object System.Drawing.Size(610, 20)
    $form.Controls.Add($lblBundle)

    $txtBundle = New-Object System.Windows.Forms.TextBox
    $txtBundle.Text = $defaultBundle
    $txtBundle.Location = New-Object System.Drawing.Point(16, 174)
    $txtBundle.Size = New-Object System.Drawing.Size(610, 24)
    $form.Controls.Add($txtBundle)

    $btnBundle = New-Object System.Windows.Forms.Button
    $btnBundle.Text = 'Browse...'
    $btnBundle.Location = New-Object System.Drawing.Point(634, 172)
    $btnBundle.Size = New-Object System.Drawing.Size(110, 26)
    $btnBundle.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Select oscar-*-ubuntu-x86_64-offline-full.zip'
        $dlg.Filter = 'OSCAR Ubuntu Offline Bundle (*.zip)|*ubuntu*offline-full*.zip;*.zip|All Files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq 'OK') { $txtBundle.Text = $dlg.FileName }
    })
    $form.Controls.Add($btnBundle)

    # 3. Identity & Security GroupBox
    $grpSec = New-Object System.Windows.Forms.GroupBox
    $grpSec.Text = '4. Target Server Identity & Hardening'
    $grpSec.Location = New-Object System.Drawing.Point(16, 208)
    $grpSec.Size = New-Object System.Drawing.Size(728, 224)
    $form.Controls.Add($grpSec)

    $lblHost = New-Object System.Windows.Forms.Label
    $lblHost.Text = 'Target Hostname:'
    $lblHost.Location = New-Object System.Drawing.Point(14, 26)
    $lblHost.Size = New-Object System.Drawing.Size(120, 20)
    $grpSec.Controls.Add($lblHost)

    $txtHost = New-Object System.Windows.Forms.TextBox
    $txtHost.Text = $InitialHost
    $txtHost.Location = New-Object System.Drawing.Point(140, 23)
    $txtHost.Size = New-Object System.Drawing.Size(200, 24)
    $grpSec.Controls.Add($txtHost)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = 'Linux Admin User:'
    $lblUser.Location = New-Object System.Drawing.Point(364, 26)
    $lblUser.Size = New-Object System.Drawing.Size(125, 20)
    $grpSec.Controls.Add($lblUser)

    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Text = $InitialUser
    $txtUser.Location = New-Object System.Drawing.Point(495, 23)
    $txtUser.Size = New-Object System.Drawing.Size(215, 24)
    $grpSec.Controls.Add($txtUser)

    $lblPw1 = New-Object System.Windows.Forms.Label
    $lblPw1.Text = 'Admin Password:'
    $lblPw1.Location = New-Object System.Drawing.Point(14, 60)
    $lblPw1.Size = New-Object System.Drawing.Size(120, 20)
    $grpSec.Controls.Add($lblPw1)

    $txtPw1 = New-Object System.Windows.Forms.TextBox
    $txtPw1.UseSystemPasswordChar = $true
    $txtPw1.Location = New-Object System.Drawing.Point(140, 57)
    $txtPw1.Size = New-Object System.Drawing.Size(200, 24)
    $grpSec.Controls.Add($txtPw1)

    $lblPw2 = New-Object System.Windows.Forms.Label
    $lblPw2.Text = 'Confirm Password:'
    $lblPw2.Location = New-Object System.Drawing.Point(364, 60)
    $lblPw2.Size = New-Object System.Drawing.Point(125, 20)
    $grpSec.Controls.Add($lblPw2)

    $txtPw2 = New-Object System.Windows.Forms.TextBox
    $txtPw2.UseSystemPasswordChar = $true
    $txtPw2.Location = New-Object System.Drawing.Point(495, 57)
    $txtPw2.Size = New-Object System.Drawing.Size(215, 24)
    $grpSec.Controls.Add($txtPw2)

    $chkSudo = New-Object System.Windows.Forms.CheckBox
    $chkSudo.Text = 'Require password for sudo (recommended when setting an Admin Password)'
    $chkSudo.Checked = $true
    $chkSudo.Location = New-Object System.Drawing.Point(14, 89)
    $chkSudo.Size = New-Object System.Drawing.Size(690, 22)
    $grpSec.Controls.Add($chkSudo)

    $chkLuks = New-Object System.Windows.Forms.CheckBox
    $chkLuks.Text = 'Enable LUKS2 Full-Disk Encryption (12+ chars):'
    $chkLuks.Location = New-Object System.Drawing.Point(14, 118)
    $chkLuks.Size = New-Object System.Drawing.Size(326, 22)
    $grpSec.Controls.Add($chkLuks)

    $txtLuks1 = New-Object System.Windows.Forms.TextBox
    $txtLuks1.UseSystemPasswordChar = $true
    $txtLuks1.Enabled = $false
    $txtLuks1.Location = New-Object System.Drawing.Point(346, 117)
    $txtLuks1.Size = New-Object System.Drawing.Size(175, 24)
    $grpSec.Controls.Add($txtLuks1)

    $txtLuks2 = New-Object System.Windows.Forms.TextBox
    $txtLuks2.UseSystemPasswordChar = $true
    $txtLuks2.Enabled = $false
    $txtLuks2.Location = New-Object System.Drawing.Point(535, 117)
    $txtLuks2.Size = New-Object System.Drawing.Size(175, 24)
    $grpSec.Controls.Add($txtLuks2)

    $chkLuks.Add_CheckedChanged({
        $txtLuks1.Enabled = $chkLuks.Checked
        $txtLuks2.Enabled = $chkLuks.Checked
    })

    $lblSsh = New-Object System.Windows.Forms.Label
    $lblSsh.Text = 'SSH Key (.pub):'
    $lblSsh.Location = New-Object System.Drawing.Point(14, 154)
    $lblSsh.Size = New-Object System.Drawing.Size(120, 20)
    $grpSec.Controls.Add($lblSsh)

    $txtSsh = New-Object System.Windows.Forms.TextBox
    $txtSsh.Text = $defaultPubKey
    $txtSsh.Location = New-Object System.Drawing.Point(140, 151)
    $txtSsh.Size = New-Object System.Drawing.Size(465, 24)
    $grpSec.Controls.Add($txtSsh)

    $btnSsh = New-Object System.Windows.Forms.Button
    $btnSsh.Text = 'Browse...'
    $btnSsh.Location = New-Object System.Drawing.Point(612, 149)
    $btnSsh.Size = New-Object System.Drawing.Size(98, 26)
    $btnSsh.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Select SSH Public Key (.pub)'
        $dlg.Filter = 'SSH Public Key (*.pub)|*.pub|All Files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq 'OK') { $txtSsh.Text = $dlg.FileName }
    })
    $grpSec.Controls.Add($btnSsh)

    $chkKeysOnly = New-Object System.Windows.Forms.CheckBox
    $chkKeysOnly.Text = 'Disable SSH password login (SSH keys only)'
    $chkKeysOnly.Location = New-Object System.Drawing.Point(140, 180)
    $chkKeysOnly.Size = New-Object System.Drawing.Size(340, 22)
    $grpSec.Controls.Add($chkKeysOnly)

    # 5. Turnkey OSCAR Site Pre-Configuration (Fresh Install)
    $grpOscar = New-Object System.Windows.Forms.GroupBox
    $grpOscar.Text = '5. Turnkey OSCAR Site Pre-Configuration (Optional - Fresh Install)'
    $grpOscar.Location = New-Object System.Drawing.Point(16, 438)
    $grpOscar.Size = New-Object System.Drawing.Size(728, 122)
    $form.Controls.Add($grpOscar)

    $lblOPw1 = New-Object System.Windows.Forms.Label
    $lblOPw1.Text = 'OSCAR Web Password:'
    $lblOPw1.Location = New-Object System.Drawing.Point(14, 26)
    $lblOPw1.Size = New-Object System.Drawing.Size(124, 20)
    $grpOscar.Controls.Add($lblOPw1)

    $txtOPw1 = New-Object System.Windows.Forms.TextBox
    $txtOPw1.UseSystemPasswordChar = $true
    $txtOPw1.Location = New-Object System.Drawing.Point(140, 23)
    $txtOPw1.Size = New-Object System.Drawing.Size(200, 24)
    $grpOscar.Controls.Add($txtOPw1)

    $lblOPw2 = New-Object System.Windows.Forms.Label
    $lblOPw2.Text = 'Confirm (14+ chars):'
    $lblOPw2.Location = New-Object System.Drawing.Point(364, 26)
    $lblOPw2.Size = New-Object System.Drawing.Size(125, 20)
    $grpOscar.Controls.Add($lblOPw2)

    $txtOPw2 = New-Object System.Windows.Forms.TextBox
    $txtOPw2.UseSystemPasswordChar = $true
    $txtOPw2.Location = New-Object System.Drawing.Point(495, 23)
    $txtOPw2.Size = New-Object System.Drawing.Size(215, 24)
    $grpOscar.Controls.Add($txtOPw2)

    $lblLanes = New-Object System.Windows.Forms.Label
    $lblLanes.Text = 'Lanes CSV / JSON:'
    $lblLanes.Location = New-Object System.Drawing.Point(14, 60)
    $lblLanes.Size = New-Object System.Drawing.Size(124, 20)
    $grpOscar.Controls.Add($lblLanes)

    $txtLanes = New-Object System.Windows.Forms.TextBox
    $txtLanes.Text = $InitialLanesFile
    $txtLanes.Location = New-Object System.Drawing.Point(140, 57)
    $txtLanes.Size = New-Object System.Drawing.Size(465, 24)
    $grpOscar.Controls.Add($txtLanes)

    $btnLanes = New-Object System.Windows.Forms.Button
    $btnLanes.Text = 'Browse...'
    $btnLanes.Location = New-Object System.Drawing.Point(612, 55)
    $btnLanes.Size = New-Object System.Drawing.Size(98, 26)
    $btnLanes.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Select Pre-Configured Lanes CSV Spreadsheet or SensorHub config.json'
        $dlg.Filter = 'OSCAR Lanes CSV or JSON (*.csv;*.json)|*.csv;*.json|All Files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq 'OK') { $txtLanes.Text = $dlg.FileName }
    })
    $grpOscar.Controls.Add($btnLanes)

    $chkAutoInit = New-Object System.Windows.Forms.CheckBox
    $chkAutoInit.Text = 'Auto-initialize OSCAR & pre-staged lanes on first boot (only add users & .pmtiles / diagram on site)'
    $chkAutoInit.Enabled = $false
    $chkAutoInit.Location = New-Object System.Drawing.Point(14, 90)
    $chkAutoInit.Size = New-Object System.Drawing.Size(698, 22)
    $grpOscar.Controls.Add($chkAutoInit)

    $syncAutoInitState = {
        $canAuto = ([bool]$txtOPw1.Text -and [bool]$txtBundle.Text.Trim())
        $wasEnabled = $chkAutoInit.Enabled
        $chkAutoInit.Enabled = $canAuto
        if ($canAuto -and -not $wasEnabled) {
            $chkAutoInit.Checked = $true
        } elseif (-not $canAuto) {
            $chkAutoInit.Checked = $false
        }
    }
    $txtOPw1.Add_TextChanged($syncAutoInitState)
    $txtBundle.Add_TextChanged($syncAutoInitState)

    # 6. Optional Extra Seed Directory
    $lblSeed = New-Object System.Windows.Forms.Label
    $lblSeed.Text = '6. Optional Extra Seed Folder (site-network.env, *.pmtiles, backup-key.txt):'
    $lblSeed.Location = New-Object System.Drawing.Point(16, 568)
    $lblSeed.Size = New-Object System.Drawing.Size(610, 20)
    $form.Controls.Add($lblSeed)

    $txtSeed = New-Object System.Windows.Forms.TextBox
    $txtSeed.Text = $InitialSeedDir
    $txtSeed.Location = New-Object System.Drawing.Point(16, 590)
    $txtSeed.Size = New-Object System.Drawing.Size(610, 24)
    $form.Controls.Add($txtSeed)

    $btnSeed = New-Object System.Windows.Forms.Button
    $btnSeed.Text = 'Browse...'
    $btnSeed.Location = New-Object System.Drawing.Point(634, 588)
    $btnSeed.Size = New-Object System.Drawing.Size(110, 26)
    $btnSeed.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Select optional extra seed folder containing site-network.env / *.pmtiles / backup-key.txt'
        if ($dlg.ShowDialog() -eq 'OK') { $txtSeed.Text = $dlg.SelectedPath }
    })
    $form.Controls.Add($btnSeed)

    # 7. Destructive Confirmation & Action Bar
    $lblConfirm = New-Object System.Windows.Forms.Label
    $lblConfirm.Text = 'Type ERASE-USB to unlock:'
    $lblConfirm.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $lblConfirm.Location = New-Object System.Drawing.Point(16, 626)
    $lblConfirm.Size = New-Object System.Drawing.Size(175, 22)
    $form.Controls.Add($lblConfirm)

    $txtConfirm = New-Object System.Windows.Forms.TextBox
    $txtConfirm.Location = New-Object System.Drawing.Point(195, 624)
    $txtConfirm.Size = New-Object System.Drawing.Size(130, 24)
    $form.Controls.Add($txtConfirm)

    $btnBuild = New-Object System.Windows.Forms.Button
    $btnBuild.Text = 'Create Bootable Autoinstall USB'
    $btnBuild.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnBuild.Enabled = $false
    $btnBuild.Location = New-Object System.Drawing.Point(340, 620)
    $btnBuild.Size = New-Object System.Drawing.Size(286, 32)
    $form.Controls.Add($btnBuild)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(634, 620)
    $btnClose.Size = New-Object System.Drawing.Size(110, 32)
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Location = New-Object System.Drawing.Point(16, 660)
    $progressBar.Size = New-Object System.Drawing.Size(728, 18)
    $form.Controls.Add($progressBar)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
    $txtLog.Location = New-Object System.Drawing.Point(16, 684)
    $txtLog.Size = New-Object System.Drawing.Size(728, 112)
    $form.Controls.Add($txtLog)

    $script:guiDiskList = @()
    $refreshUsbList = {
        $cmbUsb.Items.Clear()
        $script:guiDiskList = @(Get-CandidateUsbDisks)
        if ($script:guiDiskList.Count -eq 0) {
            [void]$cmbUsb.Items.Add('No external USB drives (>= 8 GiB) detected - insert a USB drive and click Refresh')
            $cmbUsb.SelectedIndex = 0
        } else {
            foreach ($d in $script:guiDiskList) {
                [void]$cmbUsb.Items.Add(("Disk {0} - {1} GiB - {2} (Serial: {3})" -f $d.DiskNumber, $d.SizeGiB, $d.FriendlyName, $d.SerialNumber))
            }
            $cmbUsb.SelectedIndex = 0
        }
        $btnBuild.Enabled = ($script:guiDiskList.Count -gt 0 -and $txtConfirm.Text -ceq 'ERASE-USB')
    }
    $btnRefresh.Add_Click($refreshUsbList)
    $txtConfirm.Add_TextChanged({
        $btnBuild.Enabled = ($script:guiDiskList.Count -gt 0 -and $txtConfirm.Text -ceq 'ERASE-USB')
    })
    & $refreshUsbList

    $btnBuild.Add_Click({
        if ($script:guiDiskList.Count -eq 0 -or $cmbUsb.SelectedIndex -lt 0) { return }
        $chosenDisk = $script:guiDiskList[$cmbUsb.SelectedIndex]
        if ($txtPw1.Text -cne $txtPw2.Text) {
            [System.Windows.Forms.MessageBox]::Show('Admin passwords do not match.', 'Validation Error', 'OK', 'Warning') | Out-Null
            return
        }
        if ($chkLuks.Checked) {
            if ($txtLuks1.Text.Length -lt 12) {
                [System.Windows.Forms.MessageBox]::Show('LUKS2 passphrase must be at least 12 characters.', 'Validation Error', 'OK', 'Warning') | Out-Null
                return
            }
            if ($txtLuks1.Text -cne $txtLuks2.Text) {
                [System.Windows.Forms.MessageBox]::Show('LUKS2 passphrases do not match.', 'Validation Error', 'OK', 'Warning') | Out-Null
                return
            }
        }
        if ($txtOPw1.Text -or $txtOPw2.Text) {
            if ($txtOPw1.Text.Length -lt 14) {
                [System.Windows.Forms.MessageBox]::Show('Initial OSCAR Web administrator password must contain at least 14 characters.', 'Validation Error', 'OK', 'Warning') | Out-Null
                return
            }
            if ($txtOPw1.Text -cne $txtOPw2.Text) {
                [System.Windows.Forms.MessageBox]::Show('OSCAR Web administrator passwords do not match.', 'Validation Error', 'OK', 'Warning') | Out-Null
                return
            }
        }
        $oscarWebHashVal = if ($txtOPw1.Text) { [OscarSha512Crypt]::Pbkdf2Credential($txtOPw1.Text) } else { '' }
        $pwHashVal = ''
        $reqSudo = [bool]$chkSudo.Checked
        if ($txtPw1.Text) {
            $pwHashVal = [OscarSha512Crypt]::Crypt($txtPw1.Text, '')
        } else {
            $reqSudo = $false
        }
        $luksVal = if ($chkLuks.Checked) { $txtLuks1.Text } else { '' }
        $authKeys = @()
        if ($txtSsh.Text.Trim()) {
            try {
                $authKeys = @(Read-SshKeysFromFiles @($txtSsh.Text.Trim()))
            } catch {
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'SSH Key Error', 'OK', 'Error') | Out-Null
                return
            }
        }

        $btnBuild.Enabled = $false
        $btnRefresh.Enabled = $false
        $txtLog.Clear()
        $progressBar.Value = 0

        $guiLogger = {
            param([string]$Msg, [int]$Pct)
            $ts = [DateTime]::Now.ToString('HH:mm:ss')
            $txtLog.AppendText("[$ts] $Msg`r`n")
            if ($Pct -ge 0 -and $Pct -le 100) { $progressBar.Value = $Pct }
            [System.Windows.Forms.Application]::DoEvents()
        }

        try {
            Invoke-BuildAutoinstallUsb `
                -TargetDiskNumber $chosenDisk.DiskNumber `
                -UbuntuIso $txtIso.Text.Trim('" ') `
                -BundleZip $txtBundle.Text.Trim('" ') `
                -HostVal $txtHost.Text.Trim() `
                -UserVal $txtUser.Text.Trim() `
                -PassHash $pwHashVal `
                -LuksPass $luksVal `
                -ReqSudoPw $reqSudo `
                -KeysOnly ([bool]$chkKeysOnly.Checked) `
                -AuthorizedKeys $authKeys `
                -OscarWebPassHash $oscarWebHashVal `
                -PreconfiguredLanesFile $txtLanes.Text.Trim('" ') `
                -AutoInitFirstBoot ([bool]$chkAutoInit.Checked) `
                -SeedDir $txtSeed.Text.Trim('" ') `
                -ExtraSeedFiles @() `
                -Logger $guiLogger
            $txtConfirm.Text = ''
            [System.Windows.Forms.MessageBox]::Show(
                "Autoinstall USB created and verified on Disk $($chosenDisk.DiskNumber) ($($chosenDisk.FriendlyName)).`n`nSafe to eject and boot on the target x86-64 machine.",
                'OSCAR Autoinstall USB Ready', 'OK', 'Information') | Out-Null
        } catch {
            $txtLog.AppendText("ERROR: $($_.Exception.Message)`r`n")
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Autoinstall USB Creation Failed', 'OK', 'Error') | Out-Null
        } finally {
            $btnRefresh.Enabled = $true
            $btnBuild.Enabled = ($script:guiDiskList.Count -gt 0 -and $txtConfirm.Text -ceq 'ERASE-USB')
        }
    })

    [void]$form.ShowDialog()
}

if ($Help) {
    Show-Usage
    exit 0
}

if ($TestOscarPbkdf2Only) {
    if ($TestOscarPbkdf2Only.Length -lt 14) {
        throw 'Initial OSCAR Web administrator password must contain at least 14 characters.'
    }
    Write-Output ([OscarSha512Crypt]::Pbkdf2Credential($TestOscarPbkdf2Only))
    exit 0
}

if (-not (Test-ValidHostname $Hostname)) {
    throw "Invalid -Hostname '$Hostname' (use letters, digits, and hyphens)."
}
if (-not (Test-ValidLinuxUsername $Username)) {
    throw "Invalid Linux -Username '$Username' (use lowercase letters, digits, underscore, or hyphen)."
}

$resolvedSshKeys = New-Object System.Collections.Generic.List[string]
foreach ($rk in @(Read-SshKeysFromFiles $SshKeyFile)) {
    if ($rk) { $resolvedSshKeys.Add([string]$rk) }
}

if ($PasswordFile) {
    if (-not (Test-Path -LiteralPath $PasswordFile -PathType Leaf)) {
        throw "Password file not found: $PasswordFile"
    }
    $plainFromFile = ([IO.File]::ReadAllLines($PasswordFile)[0]).TrimEnd([char[]]@([char]13, [char]10))
    if (-not $plainFromFile) {
        throw "Password file is empty: $PasswordFile"
    }
    $PasswordHash = [OscarSha512Crypt]::Crypt($plainFromFile, '')
}

$luksPassphrase = ''
if ($LuksPassphraseFile) {
    if (-not (Test-Path -LiteralPath $LuksPassphraseFile -PathType Leaf)) {
        throw "LUKS passphrase file not found: $LuksPassphraseFile"
    }
    $luksPassphrase = ([IO.File]::ReadAllLines($LuksPassphraseFile)[0]).TrimEnd([char[]]@([char]13, [char]10))
    if ($luksPassphrase.Length -lt 12) {
        throw 'LUKS full-disk encryption passphrase must contain at least 12 characters.'
    }
}

if ($OscarAdminPasswordFile) {
    if (-not (Test-Path -LiteralPath $OscarAdminPasswordFile -PathType Leaf)) {
        throw "OSCAR admin password file not found: $OscarAdminPasswordFile"
    }
    $opwFromFile = ([IO.File]::ReadAllLines($OscarAdminPasswordFile)[0]).TrimEnd([char[]]@([char]13, [char]10))
    if (-not $opwFromFile) {
        throw "OSCAR admin password file is empty: $OscarAdminPasswordFile"
    }
    if ($opwFromFile.StartsWith('# PBKDF2_PREENCODED:')) {
        $OscarAdminPasswordHash = $opwFromFile
    } elseif ($opwFromFile.StartsWith('PBKDF2WithHmacSHA1:')) {
        $OscarAdminPasswordHash = "# PBKDF2_PREENCODED:$opwFromFile"
    } else {
        if ($opwFromFile.Length -lt 14) {
            throw 'Initial OSCAR Web administrator password must contain at least 14 characters.'
        }
        $OscarAdminPasswordHash = [OscarSha512Crypt]::Pbkdf2Credential($opwFromFile)
    }
    $opwFromFile = ''
} elseif ($OscarAdminPassword) {
    if ($OscarAdminPassword.Length -lt 14) {
        throw 'Initial OSCAR Web administrator password must contain at least 14 characters.'
    }
    $OscarAdminPasswordHash = [OscarSha512Crypt]::Pbkdf2Credential($OscarAdminPassword)
    $OscarAdminPassword = ''
} elseif ($OscarAdminPasswordHash -and -not $OscarAdminPasswordHash.StartsWith('# PBKDF2_PREENCODED:')) {
    if (-not $OscarAdminPasswordHash.StartsWith('PBKDF2WithHmacSHA1:')) {
        throw '-OscarAdminPasswordHash must start with PBKDF2WithHmacSHA1: or # PBKDF2_PREENCODED:.'
    }
    $OscarAdminPasswordHash = "# PBKDF2_PREENCODED:$OscarAdminPasswordHash"
}

# Offline unit-test mode: render user-data cleanly with LF endings without touching disks
if ($RenderUserDataOnly) {
    if ($SshKeysOnly -and $resolvedSshKeys.Count -eq 0) {
        throw '-SshKeysOnly requires at least one -SshKeyFile so SSH access is not locked out.'
    }
    $rendered = Build-CustomUserData $TemplateUserData $Hostname $Username $PasswordHash $luksPassphrase ([bool]$RequireSudoPassword) ([bool]$SshKeysOnly) $resolvedSshKeys.ToArray()
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($RenderUserDataOnly), $rendered, $Utf8NoBom)
    Write-Host "Rendered cloud-init autoinstall user-data to $RenderUserDataOnly"
    exit 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'create-autoinstall-usb.ps1 must run on Windows 11 (on Ubuntu, run: sudo bash create-autoinstall-usb.sh).'
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
    throw 'Administrator privileges are required to partition and format a bootable USB drive. Run create-autoinstall-usb.bat or launch from an elevated PowerShell prompt.'
}

if ($Gui -and -not $Tui) {
    Show-AutoinstallUsbGui $IsoPath $OfflineBundlePath $Hostname $Username $LanesFile $SeedDirectory
    exit 0
}

$isInteractiveWizard = ($Tui -or ($ConfirmToken -cne 'ERASE-USB' -and ($DiskNumber -lt 0 -or -not $IsoPath)))

$candidates = @(Get-CandidateUsbDisks)
if ($DiskNumber -lt 0) {
    if ($candidates.Count -eq 0) {
        throw 'No safe removable USB drives (>= 8 GiB) detected. Plug in an external USB drive and try again.'
    }
    Write-Host "`n=== OSCAR Bare-Metal Ubuntu 24.04 Autoinstall USB Wizard ===" -ForegroundColor Cyan
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
    $defaultIso = Find-DefaultFile 'ubuntu-24.04*-live-server-amd64.iso'
    $promptIso = if ($defaultIso) { "Path to ubuntu-24.04.x-live-server-amd64.iso [$defaultIso]" } else { 'Path to ubuntu-24.04.x-live-server-amd64.iso' }
    $replyIso = Read-Host $promptIso
    $IsoPath = if ($replyIso) { $replyIso.Trim('"') } else { $defaultIso }
}

if (-not $OfflineBundlePath -and $isInteractiveWizard) {
    $defaultBundle = Find-DefaultFile 'oscar-*-ubuntu-x86_64-offline-full.zip'
    $promptBundle = if ($defaultBundle) { "Path to oscar-*-ubuntu-x86_64-offline-full.zip (Enter for default, or 'skip') [$defaultBundle]" } else { 'Path to oscar-*-ubuntu-x86_64-offline-full.zip (blank to skip)' }
    $replyBundle = Read-Host $promptBundle
    if ($replyBundle -eq 'skip') {
        $OfflineBundlePath = ''
    } elseif ($replyBundle) {
        $OfflineBundlePath = $replyBundle.Trim('"')
    } else {
        $OfflineBundlePath = $defaultBundle
    }
}

if ($isInteractiveWizard) {
    if (-not $PSBoundParameters.ContainsKey('Hostname')) {
        $replyHost = Read-Host "Target server hostname [$Hostname]"
        if ($replyHost) { $Hostname = $replyHost.Trim() }
    }
    if (-not $PSBoundParameters.ContainsKey('Username')) {
        $replyUser = Read-Host "Linux admin username [$Username]"
        if ($replyUser) { $Username = $replyUser.Trim() }
    }
    if (-not $PasswordHash) {
        $secPw1 = Read-Host "Set Linux password for '$Username' (Enter to keep bootstrap password)" -AsSecureString
        $plainPw1 = ConvertFrom-SecureStringPlain $secPw1
        if ($plainPw1) {
            $secPw2 = Read-Host "Confirm Linux password for '$Username'" -AsSecureString
            $plainPw2 = ConvertFrom-SecureStringPlain $secPw2
            if ($plainPw1 -cne $plainPw2) {
                throw 'Linux admin passwords did not match.'
            }
            $PasswordHash = [OscarSha512Crypt]::Crypt($plainPw1, '')
            $plainPw1 = ''; $plainPw2 = ''
            if (-not $PSBoundParameters.ContainsKey('RequireSudoPassword')) {
                $replySudo = Read-Host 'Require password for sudo? [Y/n]'
                if (-not $replySudo -or $replySudo -match '^[Yy]') {
                    $RequireSudoPassword = $true
                }
            }
        }
    }
    if (-not $luksPassphrase) {
        $replyLuks = Read-Host 'Enable LUKS2 full-disk encryption on the target server? [y/N]'
        if ($replyLuks -match '^[Yy]') {
            $secL1 = Read-Host 'Enter LUKS2 passphrase (12+ characters)' -AsSecureString
            $plainL1 = ConvertFrom-SecureStringPlain $secL1
            if ($plainL1.Length -lt 12) {
                throw 'LUKS2 passphrase must contain at least 12 characters.'
            }
            $secL2 = Read-Host 'Confirm LUKS2 passphrase' -AsSecureString
            $plainL2 = ConvertFrom-SecureStringPlain $secL2
            if ($plainL1 -cne $plainL2) {
                throw 'LUKS2 passphrases did not match.'
            }
            $luksPassphrase = $plainL1
            $plainL1 = ''; $plainL2 = ''
        }
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
if ($isInteractiveWizard -and $resolvedSshKeys.Count -gt 0 -and -not $PSBoundParameters.ContainsKey('SshKeysOnly')) {
    $replyKeysOnly = Read-Host "Detected $($resolvedSshKeys.Count) SSH public key(s) in ~/.ssh. Disable SSH password login (SSH keys only)? [y/N]"
    if ($replyKeysOnly -match '^[Yy]') {
        $SshKeysOnly = $true
    }
}

if ($isInteractiveWizard -and $OfflineBundlePath) {
    if (-not $OscarAdminPasswordHash) {
        $secOPw1 = Read-Host "Set initial OSCAR Web 'admin' password (14+ chars; Enter to set on site)" -AsSecureString
        $plainOPw1 = ConvertFrom-SecureStringPlain $secOPw1
        if ($plainOPw1) {
            if ($plainOPw1.Length -lt 14) {
                throw 'Initial OSCAR Web administrator password must contain at least 14 characters.'
            }
            $secOPw2 = Read-Host "Confirm initial OSCAR Web 'admin' password" -AsSecureString
            $plainOPw2 = ConvertFrom-SecureStringPlain $secOPw2
            if ($plainOPw1 -cne $plainOPw2) {
                throw 'OSCAR Web administrator passwords did not match.'
            }
            $OscarAdminPasswordHash = [OscarSha512Crypt]::Pbkdf2Credential($plainOPw1)
            $plainOPw1 = ''; $plainOPw2 = ''
        }
    }
    if (-not $LanesFile) {
        $replyLanes = Read-Host 'Optional pre-configured lanes file (lanes.csv or config.json; Enter to skip)'
        if ($replyLanes) { $LanesFile = $replyLanes.Trim('"') }
    }
    if ($OscarAdminPasswordHash -and -not $PSBoundParameters.ContainsKey('AutoInitOscar')) {
        $replyAuto = Read-Host 'Automatically initialize OSCAR & pre-staged lanes on first boot? [Y/n]'
        if (-not $replyAuto -or $replyAuto -match '^[Yy]') {
            $AutoInitOscar = $true
        }
    }
}

if (-not $SeedDirectory -and $SeedFile.Count -eq 0 -and $isInteractiveWizard) {
    $replySeed = Read-Host 'Optional extra seed folder (site-network.env, *.pmtiles, backup-key.txt; Enter to skip)'
    if ($replySeed) { $SeedDirectory = $replySeed.Trim('"') }
}

if ($ConfirmToken -cne 'ERASE-USB') {
    Write-Host "`nWARNING: ALL DATA ON USB DISK $DiskNumber ($($selectedCandidate.SizeGiB) GiB $($selectedCandidate.FriendlyName)) WILL BE ERASED!" -ForegroundColor Yellow
    $ConfirmToken = Read-Host 'Type ERASE-USB to proceed'
    if ($ConfirmToken -cne 'ERASE-USB') {
        throw 'Cancelled (expected exact confirmation token ERASE-USB).'
    }
}

if (-not $PasswordHash) {
    Write-Warning "No custom password supplied for '$Username'; change the template bootstrap password immediately after first boot via 'passwd $Username'!"
}

Invoke-BuildAutoinstallUsb `
    -TargetDiskNumber $DiskNumber `
    -UbuntuIso $IsoPath `
    -BundleZip $OfflineBundlePath `
    -HostVal $Hostname `
    -UserVal $Username `
    -PassHash $PasswordHash `
    -LuksPass $luksPassphrase `
    -ReqSudoPw ([bool]$RequireSudoPassword) `
    -KeysOnly ([bool]$SshKeysOnly) `
    -AuthorizedKeys $resolvedSshKeys.ToArray() `
    -OscarWebPassHash $OscarAdminPasswordHash `
    -PreconfiguredLanesFile $LanesFile `
    -AutoInitFirstBoot ([bool]$AutoInitOscar) `
    -SeedDir $SeedDirectory `
    -ExtraSeedFiles $SeedFile `
    -Logger $null
