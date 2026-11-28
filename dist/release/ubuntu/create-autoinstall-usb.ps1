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
    [string]$OneSheetPdfPath = '',
    [switch]$NoOneSheetPdf,
    [string]$ConfirmToken = '',
    [string]$RenderUserDataOnly = '',
    [string]$RenderOneSheetPdfOnly = '',
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

if (-not ('OscarOneSheetPdfWriter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

public sealed class OscarOneSheetSpec {
    public string Hostname;
    public string Username;
    public string LinuxPasswordPlain;
    public bool LinuxPasswordHashedOnly;
    public bool RequireSudoPassword;
    public string LuksPassphrase;
    public bool SshKeysOnly;
    public string[] SshKeys;
    public string OscarWebPasswordPlain;
    public bool OscarWebPasswordHashedOnly;
    public bool AutoInitOscar;
    public string IsoPath;
    public string BundlePath;
    public string BundleSha256;
    public string LanesFile;
    public string SeedDir;
    public string[] SeedFiles;
    public string TargetDesc;
    public string GeneratedUtc;
    public string GeneratedLocal;
    public string[] BundledManuals;

    public OscarOneSheetSpec() {
        Hostname = "oscar-host";
        Username = "oscaradmin";
        LinuxPasswordPlain = "";
        LuksPassphrase = "";
        SshKeys = new string[0];
        OscarWebPasswordPlain = "";
        IsoPath = "";
        BundlePath = "";
        BundleSha256 = "";
        LanesFile = "";
        SeedDir = "";
        SeedFiles = new string[0];
        TargetDesc = "Removable USB Drive";
        GeneratedUtc = "";
        GeneratedLocal = "";
        BundledManuals = new string[0];
    }
}

public static class OscarOneSheetPdfWriter {
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    private static string ToAscii(string val) {
        if (string.IsNullOrEmpty(val)) return "";
        StringBuilder sb = new StringBuilder(val.Length);
        for (int i = 0; i < val.Length; i++) {
            char c = val[i];
            if (c == '\u2014') { sb.Append("--"); continue; }
            if (c == '\u2013') { sb.Append('-'); continue; }
            if (c == '\u2018' || c == '\u2019') { sb.Append('\''); continue; }
            if (c == '\u201c' || c == '\u201d') { sb.Append('"'); continue; }
            if (c == '\u2022') { sb.Append('*'); continue; }
            if (c == '\u00a0') { sb.Append(' '); continue; }
            sb.Append((c >= 32 && c <= 126) ? c : '?');
        }
        return sb.ToString();
    }

    private static string PdfEscape(string s) {
        string a = ToAscii(s);
        return a.Replace("\\", "\\\\").Replace("(", "\\(").Replace(")", "\\)");
    }

    private static List<string> WrapLine(string text, int maxChars, int maxLines) {
        List<string> lines = new List<string>();
        string clean = ToAscii(text).Trim();
        if (clean.Length == 0) {
            lines.Add("-");
            return lines;
        }
        if (clean.Length <= maxChars) {
            lines.Add(clean);
            return lines;
        }
        string remaining = clean;
        while (remaining.Length > 0 && lines.Count < maxLines) {
            if (remaining.Length <= maxChars) {
                lines.Add(remaining);
                remaining = "";
                break;
            }
            int splitAt = remaining.LastIndexOf(' ', maxChars);
            if (splitAt < maxChars / 3) splitAt = maxChars;
            lines.Add(remaining.Substring(0, splitAt).TrimEnd());
            remaining = remaining.Substring(splitAt).TrimStart();
        }
        if (remaining.Length > 0 && lines.Count > 0) {
            string last = lines[lines.Count - 1];
            int keep = Math.Max(1, maxChars - 3);
            if (last.Length > keep) last = last.Substring(0, keep).TrimEnd();
            lines[lines.Count - 1] = last + "...";
        }
        return lines;
    }

    private static string FormatSize(string path) {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return "";
        long sz = new FileInfo(path).Length;
        if (sz >= 1073741824L) return string.Format(Inv, "{0:0.00} GiB", sz / 1073741824.0);
        if (sz >= 1048576L) return string.Format(Inv, "{0:0.0} MiB", sz / 1048576.0);
        if (sz >= 1024L) return string.Format(Inv, "{0:0.0} KiB", sz / 1024.0);
        return string.Format(Inv, "{0} B", sz);
    }

    private static string ParseSiteNetworkSummary(string path) {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return "";
        Dictionary<string, string> kv = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try {
            foreach (string raw in File.ReadAllLines(path)) {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int eq = line.IndexOf('=');
                if (eq <= 0) continue;
                string k = line.Substring(0, eq).Trim();
                string v = line.Substring(eq + 1).Trim().Trim('"', '\'');
                kv[k] = v;
            }
        } catch {
            return "";
        }
        List<string> parts = new List<string>();
        string pCidr;
        if (kv.TryGetValue("PRIMARY_IP_CIDR", out pCidr) && pCidr.Length > 0) {
            string pNic;
            if (!kv.TryGetValue("PRIMARY_NIC", out pNic) || pNic.Length == 0) pNic = "NIC1";
            string s = "Primary " + pNic + ": " + pCidr;
            string gw;
            if (kv.TryGetValue("PRIMARY_GATEWAY", out gw) && gw.Length > 0) s += " (GW " + gw + ")";
            string dns;
            if (kv.TryGetValue("PRIMARY_DNS", out dns) && dns.Length > 0) s += " DNS " + dns;
            parts.Add(s);
        }
        string sCidr;
        if (kv.TryGetValue("SENSOR_IP_CIDR", out sCidr) && sCidr.Length > 0) {
            string sNic;
            if (!kv.TryGetValue("SENSOR_NIC", out sNic) || sNic.Length == 0) sNic = "NIC2";
            parts.Add("Sensor " + sNic + ": " + sCidr);
        }
        string siteHost;
        if (kv.TryGetValue("OSCAR_SITE_HOSTNAME", out siteHost) && siteHost.Length > 0) {
            parts.Add("Site Host: " + siteHost);
        }
        return string.Join(" | ", parts.ToArray());
    }

    private static string ReadBackupKeySummary(string path) {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return "";
        string name = Path.GetFileName(path);
        List<string> nonEmpty = new List<string>();
        try {
            foreach (string raw in File.ReadAllLines(path)) {
                string t = raw.Trim();
                if (t.Length > 0 && !t.StartsWith("#")) nonEmpty.Add(t);
            }
        } catch {
            return "Staged at /srv/oscar/seed/" + name;
        }
        if (nonEmpty.Count == 1 && nonEmpty[0].Length <= 128) {
            bool printable = true;
            for (int i = 0; i < nonEmpty[0].Length; i++) {
                char c = nonEmpty[0][i];
                if (c < 32 || c > 126) { printable = false; break; }
            }
            if (printable) return nonEmpty[0] + "  (file: /srv/oscar/seed/" + name + ")";
        }
        return string.Format(Inv, "Key file staged at /srv/oscar/seed/{0} ({1} line(s))", name, nonEmpty.Count);
    }

    private sealed class RowDef {
        public string Label;
        public string Value;
        public bool IsMono;
        public int MaxLines;
        public RowDef(string label, string value, bool isMono, int maxLines) {
            Label = label; Value = value; IsMono = isMono; MaxLines = maxLines;
        }
    }

    private sealed class PdfCanvas {
        public List<string> Cmds = new List<string>();
        public double CurY = 758.0;
        public const double MarginL = 36.0;
        public const double ContentW = 540.0;

        public void Rect(double x, double y, double w, double h, double[] fill, double[] stroke, double lw) {
            Cmds.Add("q");
            if (stroke != null) {
                Cmds.Add(string.Format(Inv, "{0:0.00} w", lw));
                Cmds.Add(string.Format(Inv, "{0:0.000} {1:0.000} {2:0.000} RG", stroke[0], stroke[1], stroke[2]));
            }
            if (fill != null) {
                Cmds.Add(string.Format(Inv, "{0:0.000} {1:0.000} {2:0.000} rg", fill[0], fill[1], fill[2]));
            }
            string op = (fill != null && stroke != null) ? "B" : (fill != null ? "f" : "S");
            Cmds.Add(string.Format(Inv, "{0:0.00} {1:0.00} {2:0.00} {3:0.00} re {4}", x, y, w, h, op));
            Cmds.Add("Q");
        }

        public void Line(double x1, double y1, double x2, double y2, double[] stroke, double lw) {
            Cmds.Add("q");
            Cmds.Add(string.Format(Inv, "{0:0.00} w", lw));
            Cmds.Add(string.Format(Inv, "{0:0.000} {1:0.000} {2:0.000} RG", stroke[0], stroke[1], stroke[2]));
            Cmds.Add(string.Format(Inv, "{0:0.00} {1:0.00} m {2:0.00} {3:0.00} l S", x1, y1, x2, y2));
            Cmds.Add("Q");
        }

        public void Text(double x, double y, string text, string font, double size, double[] color) {
            Cmds.Add("q");
            Cmds.Add(string.Format(Inv, "{0:0.000} {1:0.000} {2:0.000} rg", color[0], color[1], color[2]));
            Cmds.Add(string.Format(Inv, "BT /{0} {1:0.0} Tf 1 0 0 1 {2:0.00} {3:0.00} Tm ({4}) Tj ET", font, size, x, y, PdfEscape(text)));
            Cmds.Add("Q");
        }
    }

    public static void WritePdf(string outputPath, OscarOneSheetSpec spec) {
        string hostname = string.IsNullOrEmpty(spec.Hostname) ? "oscar-host" : spec.Hostname;
        string username = string.IsNullOrEmpty(spec.Username) ? "oscaradmin" : spec.Username;

        List<string> stagedSeedNames = new List<string>();
        string siteNetPath = "";
        string backupKeyPath = "";

        Action<string, string> considerSeed = delegate(string fullPath, string relName) {
            if (!stagedSeedNames.Contains(relName)) stagedSeedNames.Add(relName);
            string lower = Path.GetFileName(relName).ToLowerInvariant();
            if (lower == "site-network.env" && siteNetPath.Length == 0) siteNetPath = fullPath;
            if (lower.Contains("backup") && lower.Contains("key") && lower.EndsWith(".txt") && backupKeyPath.Length == 0) backupKeyPath = fullPath;
        };

        if (!string.IsNullOrEmpty(spec.SeedDir) && Directory.Exists(spec.SeedDir)) {
            string[] allFiles = Directory.GetFiles(spec.SeedDir, "*", SearchOption.AllDirectories);
            Array.Sort(allFiles, StringComparer.OrdinalIgnoreCase);
            string rootNorm = Path.GetFullPath(spec.SeedDir).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
            foreach (string fp in allFiles) {
                string fullNorm = Path.GetFullPath(fp);
                string rel = fullNorm.StartsWith(rootNorm, StringComparison.OrdinalIgnoreCase)
                    ? fullNorm.Substring(rootNorm.Length).Replace('\\', '/')
                    : Path.GetFileName(fp);
                considerSeed(fp, rel);
            }
        }
        if (spec.SeedFiles != null) {
            foreach (string sf in spec.SeedFiles) {
                if (!string.IsNullOrEmpty(sf) && File.Exists(sf)) considerSeed(sf, Path.GetFileName(sf));
            }
        }
        if (!string.IsNullOrEmpty(spec.LanesFile) && File.Exists(spec.LanesFile)) {
            considerSeed(spec.LanesFile, Path.GetFileName(spec.LanesFile));
        }
        if (!string.IsNullOrEmpty(spec.OscarWebPasswordPlain) || spec.OscarWebPasswordHashedOnly) {
            if (!stagedSeedNames.Contains("oscar-admin-password.txt (PBKDF2 hash)")) stagedSeedNames.Add("oscar-admin-password.txt (PBKDF2 hash)");
        }
        if (spec.AutoInitOscar) {
            if (!stagedSeedNames.Contains("auto-provision.env")) stagedSeedNames.Add("auto-provision.env");
        }

        string siteNetSummary = ParseSiteNetworkSummary(siteNetPath);
        string backupKeySummary = ReadBackupKeySummary(backupKeyPath);

        string oscarVersion = "OS-Only USB";
        if (!string.IsNullOrEmpty(spec.BundlePath)) {
            string bName = Path.GetFileName(spec.BundlePath);
            Match m = Regex.Match(bName, @"oscar-([0-9]+\.[0-9]+\.[0-9]+[^\s/\\]*?)-ubuntu", RegexOptions.IgnoreCase);
            oscarVersion = m.Success ? ("v" + m.Groups[1].Value) : bName;
        }

        string linuxPwDisplay;
        bool linuxPwMono;
        if (!string.IsNullOrEmpty(spec.LinuxPasswordPlain)) {
            linuxPwDisplay = spec.LinuxPasswordPlain;
            linuxPwMono = true;
        } else if (spec.LinuxPasswordHashedOnly) {
            linuxPwDisplay = "[Pre-hashed SHA-512 supplied; plaintext unavailable]";
            linuxPwMono = false;
        } else {
            linuxPwDisplay = "OscarChangeMe!24  (TEMPLATE DEFAULT -- run: passwd " + username + ")";
            linuxPwMono = true;
        }

        string oscarWebDisplay;
        bool oscarWebMono;
        if (!string.IsNullOrEmpty(spec.OscarWebPasswordPlain)) {
            oscarWebDisplay = "User: admin   |   Pass: " + spec.OscarWebPasswordPlain;
            oscarWebMono = true;
        } else if (spec.OscarWebPasswordHashedOnly) {
            oscarWebDisplay = "User: admin   |   Pass: [Pre-encoded PBKDF2 hash supplied]";
            oscarWebMono = false;
        } else {
            oscarWebDisplay = "User: admin   |   Pass: [Set 14+ char password during first-boot wizard]";
            oscarWebMono = false;
        }

        string luksDisplay = !string.IsNullOrEmpty(spec.LuksPassphrase)
            ? ("ENABLED -- Passphrase: " + spec.LuksPassphrase)
            : "Disabled (unencrypted 100% internal NVMe/SSD LVM)";
        bool luksMono = !string.IsNullOrEmpty(spec.LuksPassphrase);

        string[] keysArr = spec.SshKeys ?? new string[0];
        List<string> sshLabels = new List<string>();
        int shownKeys = Math.Min(4, keysArr.Length);
        for (int i = 0; i < shownKeys; i++) {
            string[] parts = keysArr[i].Trim().Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length >= 3) sshLabels.Add(parts[0] + " (" + parts[2] + ")");
            else if (parts.Length >= 1) {
                string tail = parts[parts.Length - 1];
                if (tail.Length > 12) tail = tail.Substring(tail.Length - 12);
                sshLabels.Add(parts[0] + " (..." + tail + ")");
            }
        }
        if (keysArr.Length > 4) sshLabels.Add("+" + (keysArr.Length - 4).ToString(Inv) + " more");
        string sshPolicy = spec.SshKeysOnly ? "SSH keys ONLY (password login disabled)" : "Password + SSH key login allowed";
        string sshDisplay = keysArr.Length > 0
            ? (sshPolicy + " | " + keysArr.Length.ToString(Inv) + " key(s): " + string.Join(", ", sshLabels.ToArray()))
            : (sshPolicy + " | No SSH public keys staged");

        string isoDisplay = !string.IsNullOrEmpty(spec.IsoPath)
            ? (Path.GetFileName(spec.IsoPath) + " (" + FormatSize(spec.IsoPath) + ")")
            : "Not specified";
        string bundleDisplay = !string.IsNullOrEmpty(spec.BundlePath)
            ? (Path.GetFileName(spec.BundlePath) + " (" + FormatSize(spec.BundlePath) + ") -> /srv/oscar/")
            : "None (OS-only Ubuntu 24.04 autoinstall USB)";
        string shaDisplay = !string.IsNullOrEmpty(spec.BundleSha256)
            ? spec.BundleSha256
            : (!string.IsNullOrEmpty(spec.BundlePath) ? "Verified during USB write" : "N/A (no offline bundle)");
        string lanesDisplay = !string.IsNullOrEmpty(spec.LanesFile)
            ? (Path.GetFileName(spec.LanesFile) + " -> /srv/oscar/seed/" + Path.GetFileName(spec.LanesFile))
            : "None pre-staged (configure in OSCAR UI or wizard)";
        string seedsDisplay = stagedSeedNames.Count > 0 ? string.Join(", ", stagedSeedNames.ToArray()) : "None";
        string manualsDisplay = (spec.BundledManuals != null && spec.BundledManuals.Length > 0)
            ? string.Join(", ", spec.BundledManuals)
            : "Included inside offline bundle (/srv/oscar/)";
        string modeDisplay = spec.AutoInitOscar
            ? "Turnkey Unattended Auto-Init (oscar-autoprovision.service)"
            : "Interactive First-Boot Wizard (auto-opens on login, or: sudo oscar-wizard)";

        double[] NAVY = new double[] { 0.059, 0.153, 0.267 };
        double[] SLATE = new double[] { 0.118, 0.227, 0.373 };
        double[] TEAL = new double[] { 0.051, 0.580, 0.533 };
        double[] BADGE_DARK = new double[] { 0.200, 0.255, 0.333 };
        double[] AMBER_BG = new double[] { 0.996, 0.953, 0.780 };
        double[] AMBER_BORDER = new double[] { 0.851, 0.467, 0.024 };
        double[] AMBER_TEXT = new double[] { 0.573, 0.251, 0.055 };
        double[] ROW_ALT = new double[] { 0.969, 0.980, 0.988 };
        double[] WHITE = new double[] { 1.0, 1.0, 1.0 };
        double[] BORDER = new double[] { 0.796, 0.835, 0.882 };
        double[] TEXT_DARK = new double[] { 0.086, 0.125, 0.184 };
        double[] TEXT_MUTED = new double[] { 0.278, 0.333, 0.412 };
        double[] SUB_COLOR = new double[] { 0.820, 0.870, 0.930 };
        double[] CODE_BG = new double[] { 0.945, 0.961, 0.976 };

        PdfCanvas c = new PdfCanvas();

        // Header Banner
        double headerH = 48.0;
        c.Rect(PdfCanvas.MarginL, c.CurY - headerH, PdfCanvas.ContentW, headerH, NAVY, null, 0.0);
        c.Text(PdfCanvas.MarginL + 12, c.CurY - 19, "OSCAR BARE-METAL DEPLOYMENT -- TECHNICIAN ONE-SHEET", "F2", 12.5, WHITE);
        string tsShown = !string.IsNullOrEmpty(spec.GeneratedUtc) ? spec.GeneratedUtc : spec.GeneratedLocal;
        string subLine = "Target Host: " + hostname + "   |   OSCAR: " + oscarVersion + "   |   Generated: " + tsShown;
        if (subLine.Length > 95) subLine = subLine.Substring(0, 95);
        c.Text(PdfCanvas.MarginL + 12, c.CurY - 36, subLine, "F1", 8.5, SUB_COLOR);

        string badgeTxt = spec.AutoInitOscar ? "TURNKEY AUTO-INIT" : "INTERACTIVE WIZARD";
        double badgeW = spec.AutoInitOscar ? 100.0 : 106.0;
        double badgeX = PdfCanvas.MarginL + PdfCanvas.ContentW - badgeW - 10.0;
        c.Rect(badgeX, c.CurY - 33.0, badgeW, 19.0, spec.AutoInitOscar ? TEAL : BADGE_DARK, null, 0.0);
        c.Text(badgeX + (spec.AutoInitOscar ? 11.0 : 9.0), c.CurY - 26.5, badgeTxt, "F2", 7.8, WHITE);
        c.CurY -= (headerH + 6.0);

        // Security Notice Callout Strip
        double warnH = 24.0;
        c.Rect(PdfCanvas.MarginL, c.CurY - warnH, PdfCanvas.ContentW, warnH, AMBER_BG, AMBER_BORDER, 0.9);
        c.Text(PdfCanvas.MarginL + 8, c.CurY - 10.5, "SENSITIVE CREDENTIALS -- PRINT FOR SITE SECURITY BINDER & HANDOVER (LOCAL WORKSTATION COPY ONLY)", "F2", 7.6, AMBER_TEXT);
        c.Text(PdfCanvas.MarginL + 8, c.CurY - 20.0, "This one-sheet is NEVER written to the USB drive. Print now for field setup, then securely delete this PDF after site handover.", "F1", 7.4, AMBER_TEXT);
        c.CurY -= (warnH + 7.0);

        Action<string> drawSectionHeader = delegate(string title) {
            double h = 16.5;
            c.Rect(PdfCanvas.MarginL, c.CurY - h, PdfCanvas.ContentW, h, SLATE, null, 0.0);
            c.Text(PdfCanvas.MarginL + 8, c.CurY - 11.5, title, "F2", 8.6, WHITE);
            c.CurY -= h;
        };

        Action<RowDef[]> drawKvTable = delegate(RowDef[] rows) {
            double labelW = 142.0;
            double valX = PdfCanvas.MarginL + labelW + 6.0;
            double topY = c.CurY;
            for (int i = 0; i < rows.Length; i++) {
                RowDef r = rows[i];
                string fn = r.IsMono ? "F4" : "F1";
                double fs = r.IsMono ? 8.1 : 8.2;
                int mc = r.IsMono ? 66 : 80;
                List<string> wrapped = WrapLine(r.Value, mc, r.MaxLines);
                double rowH = Math.Max(14.5, 4.5 + wrapped.Count * 10.2);
                c.Rect(PdfCanvas.MarginL, c.CurY - rowH, PdfCanvas.ContentW, rowH, (i % 2 == 1) ? ROW_ALT : WHITE, null, 0.0);
                c.Line(PdfCanvas.MarginL, c.CurY - rowH, PdfCanvas.MarginL + PdfCanvas.ContentW, c.CurY - rowH, BORDER, 0.45);
                c.Text(PdfCanvas.MarginL + 7, c.CurY - 10.5, r.Label, "F2", 8.0, TEXT_MUTED);
                double ly = c.CurY - 10.5;
                foreach (string wl in wrapped) {
                    c.Text(valX, ly, wl, fn, fs, TEXT_DARK);
                    ly -= 10.2;
                }
                c.CurY -= rowH;
            }
            c.Line(PdfCanvas.MarginL + labelW, topY, PdfCanvas.MarginL + labelW, c.CurY, BORDER, 0.5);
            c.Rect(PdfCanvas.MarginL, c.CurY, PdfCanvas.ContentW, topY - c.CurY, null, BORDER, 0.6);
            c.CurY -= 7.0;
        };

        drawSectionHeader("1. SYSTEM IDENTITY, PASSWORDS & PASSPHRASES");
        drawKvTable(new RowDef[] {
            new RowDef("Target Hostname / URLs", hostname + "  |  https://" + hostname + "/  |  /sensorhub/admin", true, 2),
            new RowDef("Linux Admin Username", username + "   (SSH: ssh " + username + "@" + hostname + ")", true, 1),
            new RowDef("Linux Admin Password", linuxPwDisplay, linuxPwMono, 2),
            new RowDef("Sudo Privilege Policy", spec.RequireSudoPassword ? "Password required for sudo" : "Passwordless sudo (NOPASSWD enabled)", false, 1),
            new RowDef("LUKS2 Disk Encryption", luksDisplay, luksMono, 2),
            new RowDef("SSH Access & Keys", sshDisplay, false, 2),
            new RowDef("OSCAR Web Admin Login", oscarWebDisplay, oscarWebMono, 2),
            new RowDef("Backup Encryption Key", backupKeySummary.Length > 0 ? backupKeySummary : "Not pre-staged (configure during USB backup setup)", backupKeySummary.Length > 0, 2),
            new RowDef("Staged Site Network", siteNetSummary.Length > 0 ? siteNetSummary : "Non-blocking DHCP (configure static IP in First-Boot Wizard)", siteNetSummary.Length > 0, 2)
        });

        drawSectionHeader("2. INSTALLATION MEDIA, VERIFIED CHECKSUMS & PRE-STAGED FILES");
        drawKvTable(new RowDef[] {
            new RowDef("Target USB / Image", string.IsNullOrEmpty(spec.TargetDesc) ? "Removable USB Drive" : spec.TargetDesc, false, 1),
            new RowDef("Ubuntu 24.04 Live ISO", isoDisplay, false, 1),
            new RowDef("OSCAR Offline Bundle", bundleDisplay, false, 2),
            new RowDef("Verified Bundle SHA-256", shaDisplay, true, 2),
            new RowDef("Pre-Staged Lanes/Config", lanesDisplay, false, 2),
            new RowDef("Staged Seed Files", seedsDisplay, false, 2),
            new RowDef("Bundled Manuals / Docs", manualsDisplay, false, 2),
            new RowDef("First-Boot Mode", modeDisplay, false, 1)
        });

        drawSectionHeader("3. POST-AUTOINSTALL FIELD SETUP & ACCESS CHECKLIST");
        string step4 = spec.AutoInitOscar
            ? ("4. Verify Turnkey OSCAR: Run 'sudo bash /srv/oscar/oscar-*/oscar.sh status' (log: /var/log/oscar-autoprovision.log). Open https://" + hostname + "/ as 'admin', register site users/Passkeys, and upload .pmtiles or site diagram if not pre-staged.")
            : "4. Run First-Boot Wizard: The OSCAR Provisioning Wizard auto-launches on first login (or run 'sudo oscar-wizard') to optimize host offline, apply static IP, restore a backup, or initialize OSCAR.";

        string[] steps = new string[] {
            "1. Boot Target Server: Insert this USB into the target x86-64 machine (no internet needed) and select USB in UEFI Boot Menu.",
            "2. Complete Unattended Install: Ubuntu 24.04 installs onto the internal NVMe/SSD (100% LVM; USB drives protected) and unpacks OSCAR into /srv/oscar/. Remove USB when prompted and press Enter.",
            "3. Unlock & Sign In: " + (!string.IsNullOrEmpty(spec.LuksPassphrase) ? "Enter the LUKS2 Boot Passphrase above when prompted. " : "") + "Log in on console or SSH as '" + username + "'.",
            step4,
            "5. Hardware & Ops Check: Verify SensorHub Admin (/sensorhub/admin), time sync, and lanes. Power 1-4 TB M.2 NVMe USB backup drives via a mains-powered USB 3.2 Gen 2 hub or 15W USB-C port (USB-NVMe quirks pre-installed).",
            "6. Handover & Cleanup: Record the assigned site IP below, file this printed one-sheet in the site binder, and securely delete the local PDF copy from the staging workstation."
        };

        List<List<string>> wrappedSteps = new List<List<string>>();
        int totalStepLines = 0;
        foreach (string st in steps) {
            List<string> ws = WrapLine(st, 124, 3);
            wrappedSteps.Add(ws);
            totalStepLines += ws.Count;
        }
        double panelTop = c.CurY;
        double quickCmdH = 26.0;
        double lineStep = 9.5;
        double stepGap = 2.5;
        double panelH = 8.0 + totalStepLines * lineStep + wrappedSteps.Count * stepGap + quickCmdH + 6.0;
        if (panelTop - panelH < 94.0) {
            lineStep = 8.6;
            stepGap = 1.6;
            panelH = 6.0 + totalStepLines * lineStep + wrappedSteps.Count * stepGap + quickCmdH + 5.0;
        }

        c.Rect(PdfCanvas.MarginL, panelTop - panelH, PdfCanvas.ContentW, panelH, WHITE, BORDER, 0.6);
        double cy = panelTop - 11.5;
        foreach (List<string> ws in wrappedSteps) {
            c.Rect(PdfCanvas.MarginL + 8, cy - 1.0, 6.5, 6.5, WHITE, SLATE, 0.6);
            foreach (string sl in ws) {
                c.Text(PdfCanvas.MarginL + 19, cy, sl, "F1", 7.8, TEXT_DARK);
                cy -= lineStep;
            }
            cy -= stepGap;
        }

        double cmdBoxY = panelTop - panelH + 4.5;
        c.Rect(PdfCanvas.MarginL + 6, cmdBoxY, PdfCanvas.ContentW - 12, quickCmdH, CODE_BG, BORDER, 0.5);
        c.Text(PdfCanvas.MarginL + 12, cmdBoxY + 15.5, "Commands:  sudo bash /srv/oscar/oscar-*/oscar.sh status   |   sudo oscar-wizard   |   oscar.sh reset-admin-password", "F3", 7.3, NAVY);
        c.Text(PdfCanvas.MarginL + 12, cmdBoxY + 5.5, "Paths:     Release: /srv/oscar/   |   Seeds: /srv/oscar/seed/   |   Auto-Init Log: /var/log/oscar-autoprovision.log", "F3", 7.3, NAVY);

        double signTop = Math.Min(panelTop - panelH - 6.0, 86.0);
        double signH = 44.0;
        double signY = Math.Max(38.0, signTop - signH);
        c.Rect(PdfCanvas.MarginL, signY, PdfCanvas.ContentW, signH, ROW_ALT, BORDER, 0.6);
        c.Text(PdfCanvas.MarginL + 8, signY + 33.5, "FIELD DEPLOYMENT SIGN-OFF", "F2", 7.8, SLATE);
        c.Text(PdfCanvas.MarginL + 8, signY + 20.5, "Site / Facility: _____________________________________   Assigned IP: _________________________   Date: __________________", "F1", 8.0, TEXT_DARK);
        c.Text(PdfCanvas.MarginL + 8, signY + 7.5, "Technician: __________________________________________   Signature: ___________________________   Binder Ref: ____________", "F1", 8.0, TEXT_DARK);

        c.Text(PdfCanvas.MarginL, 24.0, "OSCAR Bare-Metal Autoinstall USB Creator   |   Host: " + hostname + "   |   Page 1 of 1   |   Local workstation copy only (NOT stored on USB)", "F1", 7.0, TEXT_MUTED);

        byte[] streamBytes = Encoding.GetEncoding(28591).GetBytes(string.Join("\n", c.Cmds.ToArray()) + "\n");
        Encoding ascii = Encoding.ASCII;

        List<byte[]> objects = new List<byte[]>();
        objects.Add(ascii.GetBytes("<< /Type /Catalog /Pages 2 0 R >>"));
        objects.Add(ascii.GetBytes("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"));
        objects.Add(ascii.GetBytes("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R /F3 6 0 R /F4 7 0 R >> >> /Contents 8 0 R >>"));
        objects.Add(ascii.GetBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"));
        objects.Add(ascii.GetBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"));
        objects.Add(ascii.GetBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>"));
        objects.Add(ascii.GetBytes("<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold /Encoding /WinAnsiEncoding >>"));

        using (MemoryStream stObj = new MemoryStream()) {
            byte[] hdr = ascii.GetBytes(string.Format(Inv, "<< /Length {0} >>\nstream\n", streamBytes.Length));
            byte[] ftr = ascii.GetBytes("endstream");
            stObj.Write(hdr, 0, hdr.Length);
            stObj.Write(streamBytes, 0, streamBytes.Length);
            stObj.Write(ftr, 0, ftr.Length);
            objects.Add(stObj.ToArray());
        }

        string parentDir = Path.GetDirectoryName(Path.GetFullPath(outputPath));
        if (!string.IsNullOrEmpty(parentDir) && !Directory.Exists(parentDir)) {
            Directory.CreateDirectory(parentDir);
        }

        using (MemoryStream ms = new MemoryStream()) {
            byte[] pdfHeader = new byte[] { 0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a, 0x25, 0xe2, 0xe3, 0xcf, 0xd3, 0x0a };
            ms.Write(pdfHeader, 0, pdfHeader.Length);
            List<long> offsets = new List<long>();
            offsets.Add(0);
            for (int i = 0; i < objects.Count; i++) {
                offsets.Add(ms.Position);
                byte[] obHdr = ascii.GetBytes(string.Format(Inv, "{0} 0 obj\n", i + 1));
                byte[] obFtr = ascii.GetBytes("\nendobj\n");
                ms.Write(obHdr, 0, obHdr.Length);
                ms.Write(objects[i], 0, objects[i].Length);
                ms.Write(obFtr, 0, obFtr.Length);
            }
            long xrefPos = ms.Position;
            StringBuilder xref = new StringBuilder();
            xref.AppendFormat(Inv, "xref\n0 {0}\n", objects.Count + 1);
            xref.Append("0000000000 65535 f \n");
            for (int i = 1; i < offsets.Count; i++) {
                xref.AppendFormat(Inv, "{0:0000000000} 00000 n \n", offsets[i]);
            }
            xref.AppendFormat(Inv, "trailer\n<< /Size {0} /Root 1 0 R >>\nstartxref\n{1}\n%%EOF\n", objects.Count + 1, xrefPos);
            byte[] xrefBytes = ascii.GetBytes(xref.ToString());
            ms.Write(xrefBytes, 0, xrefBytes.Length);
            File.WriteAllBytes(outputPath, ms.ToArray());
        }
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
      -OfflineBundlePath C:\Downloads\oscar-3.12.0-ubuntu-x86_64-offline-full.zip `
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
      -OneSheetPdfPath "$HOME\Desktop\OSCAR-Install-OneSheet.pdf" `
      -ConfirmToken ERASE-USB

Modes:
  -Gui           Open the native Windows desktop GUI (default via create-autoinstall-usb.bat).
  -Tui           Run the step-by-step interactive terminal wizard (default in PowerShell consoles).
  CLI flags      Run 100% non-interactively for automated staging.
  -NoOneSheetPdf Skip generating the local printable Technician Handover One-Sheet PDF.

Safety guarantees:
  - Strictly blocks internal NVMe/SATA/SAS OS drives, system/boot disks, the drive
    hosting Windows or OSCAR, and any USB drive containing an OSCAR_BACKUP volume.
  - Requires ZERO third-party tools (no Rufus, OpenSSL, or 7-Zip needed): hashes Linux
    SHA-512 ($6$) passwords natively and builds a 3-partition GPT UEFI (Secure Boot
    compatible) USB drive with UBUNTU_LIVE, CIDATA, and OSCAR_MEDIA + verified SHA-256.
  - Generates a printable 1-page Technician Handover One-Sheet PDF strictly on this
    local workstation (restricted user-only NTFS ACL, NEVER written to the USB drive)
    containing usernames, passwords, passphrases, SHA-256 checksums, staged files,
    and post-autoinstall setup steps.
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

function Resolve-DefaultOneSheetPdfPath([string]$HostVal) {
    $slug = [Regex]::Replace($HostVal, '[^A-Za-z0-9._-]', '_')
    if (-not $slug) { $slug = 'oscar-host' }
    $ts = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
    $baseDir = [Environment]::GetFolderPath('Desktop')
    if (-not $baseDir -or -not (Test-Path -LiteralPath $baseDir -PathType Container)) {
        $baseDir = [Environment]::GetFolderPath('MyDocuments')
    }
    if (-not $baseDir -or -not (Test-Path -LiteralPath $baseDir -PathType Container)) {
        $baseDir = (Get-Location).Path
    }
    return (Join-Path $baseDir "OSCAR-Install-OneSheet-$slug-$ts.pdf")
}

function Protect-LocalOneSheetPdfAcl([string]$PdfPath) {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return }
    if (-not (Test-Path -LiteralPath $PdfPath -PathType Leaf)) { return }
    try {
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)
        $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $sysSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
        foreach ($sid in @($currentSid, $sysSid, $adminSid)) {
            if ($sid) {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $sid,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.AddAccessRule($rule)
            }
        }
        [System.IO.File]::SetAccessControl($PdfPath, $acl)
    } catch {}
}

function New-TechnicianOneSheetPdf(
    [string]$OutputPath,
    [string]$HostVal,
    [string]$UserVal,
    [string]$LinuxPasswordPlain,
    [bool]$LinuxPasswordHashedOnly,
    [bool]$ReqSudoPw,
    [string]$LuksPass,
    [bool]$KeysOnly,
    [string[]]$AuthorizedKeys,
    [string]$OscarWebPasswordPlain,
    [bool]$OscarWebPasswordHashedOnly,
    [bool]$AutoInitFirstBoot,
    [string]$UbuntuIso,
    [string]$BundleZip,
    [string]$BundleSha256,
    [string]$PreconfiguredLanesFile,
    [string]$SeedDir,
    [string[]]$ExtraSeedFiles,
    [string]$TargetDesc,
    [string[]]$BundledManuals
) {
    $fullOut = [IO.Path]::GetFullPath($OutputPath)
    $spec = New-Object OscarOneSheetSpec
    $spec.Hostname = $HostVal
    $spec.Username = $UserVal
    $spec.LinuxPasswordPlain = $LinuxPasswordPlain
    $spec.LinuxPasswordHashedOnly = $LinuxPasswordHashedOnly
    $spec.RequireSudoPassword = $ReqSudoPw
    $spec.LuksPassphrase = $LuksPass
    $spec.SshKeysOnly = $KeysOnly
    $spec.SshKeys = if ($AuthorizedKeys) { [string[]]$AuthorizedKeys } else { @() }
    $spec.OscarWebPasswordPlain = $OscarWebPasswordPlain
    $spec.OscarWebPasswordHashedOnly = $OscarWebPasswordHashedOnly
    $spec.AutoInitOscar = $AutoInitFirstBoot
    $spec.IsoPath = $UbuntuIso
    $spec.BundlePath = $BundleZip
    $spec.BundleSha256 = $BundleSha256
    $spec.LanesFile = $PreconfiguredLanesFile
    $spec.SeedDir = $SeedDir
    $spec.SeedFiles = if ($ExtraSeedFiles) { [string[]]$ExtraSeedFiles } else { @() }
    $spec.TargetDesc = $TargetDesc
    $spec.GeneratedUtc = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm UTC')
    $spec.GeneratedLocal = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm')
    $spec.BundledManuals = if ($BundledManuals) { [string[]]$BundledManuals } else { @() }

    [OscarOneSheetPdfWriter]::WritePdf($fullOut, $spec)
    Protect-LocalOneSheetPdfAcl $fullOut
    return $fullOut
}

function Invoke-BuildAutoinstallUsb(
    [int]$TargetDiskNumber,
    [string]$UbuntuIso,
    [string]$BundleZip,
    [string]$HostVal,
    [string]$UserVal,
    [string]$PassHash,
    [string]$LinuxPasswordPlain,
    [string]$LuksPass,
    [bool]$ReqSudoPw,
    [bool]$KeysOnly,
    [string[]]$AuthorizedKeys,
    [string]$OscarWebPassHash,
    [string]$OscarWebPasswordPlain,
    [string]$PreconfiguredLanesFile,
    [bool]$AutoInitFirstBoot,
    [string]$SeedDir,
    [string[]]$ExtraSeedFiles,
    [string]$OneSheetPdfOutPath,
    [bool]$SkipOneSheetPdf,
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

        $verifiedBundleSha = ''
        $bundledManualNames = New-Object System.Collections.Generic.List[string]
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
            $verifiedBundleSha = $actualUsbSha
            [IO.File]::WriteAllText($destShaFile, "$actualUsbSha *$bundleLeaf`n", $Utf8NoBom)
            $bundleParentDir = Split-Path -Parent $BundleZip
            foreach ($searchDir in @($bundleParentDir, (Join-Path (Join-Path $ReleaseDir 'documentation') 'operator-manual'))) {
                if ($searchDir -and (Test-Path -LiteralPath $searchDir -PathType Container)) {
                    Get-ChildItem -LiteralPath $searchDir -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -like 'OSCAR-*-Administrator-Operator-Manual-*.pdf' -or $_.Name -like 'OSCAR-*-SHA256SUMS.txt' } |
                        ForEach-Object {
                            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $mediaDrive $_.Name) -Force
                            if (-not $bundledManualNames.Contains($_.Name)) { $bundledManualNames.Add($_.Name) }
                        }
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

        & $emit 'Flushing volume caches to USB media...' 96
        foreach ($dl in @($liveDrive[0], $cidataDrive[0], $mediaDrive[0])) {
            Write-VolumeCache -DriveLetter $dl -ErrorAction SilentlyContinue
        }

        $savedPdfPath = ''
        if (-not $SkipOneSheetPdf) {
            $pdfTarget = if ($OneSheetPdfOutPath) { $OneSheetPdfOutPath } else { Resolve-DefaultOneSheetPdfPath $HostVal }
            $usbSummary = "Disk $TargetDiskNumber ($($selectedCandidate.SizeGiB) GiB $($selectedCandidate.FriendlyName), Serial: $($selectedCandidate.SerialNumber))"
            & $emit "Generating printable Technician Handover One-Sheet PDF on local workstation (never stored on USB)..." 98
            $savedPdfPath = New-TechnicianOneSheetPdf `
                -OutputPath $pdfTarget `
                -HostVal $HostVal `
                -UserVal $UserVal `
                -LinuxPasswordPlain $LinuxPasswordPlain `
                -LinuxPasswordHashedOnly ([bool]($PassHash -and -not $LinuxPasswordPlain)) `
                -ReqSudoPw $ReqSudoPw `
                -LuksPass $LuksPass `
                -KeysOnly $KeysOnly `
                -AuthorizedKeys $AuthorizedKeys `
                -OscarWebPasswordPlain $OscarWebPasswordPlain `
                -OscarWebPasswordHashedOnly ([bool]($OscarWebPassHash -and -not $OscarWebPasswordPlain)) `
                -AutoInitFirstBoot $AutoInitFirstBoot `
                -UbuntuIso $UbuntuIso `
                -BundleZip $BundleZip `
                -BundleSha256 $verifiedBundleSha `
                -PreconfiguredLanesFile $PreconfiguredLanesFile `
                -SeedDir $SeedDir `
                -ExtraSeedFiles $ExtraSeedFiles `
                -TargetDesc $usbSummary `
                -BundledManuals $bundledManualNames.ToArray()
            & $emit "TECHNICIAN ONE-SHEET PDF (local only, NEVER stored on USB): $savedPdfPath" 99
        }

        & $emit "SUCCESS: OSCAR Bare-Metal Autoinstall USB ready on Disk $TargetDiskNumber ($($selectedCandidate.FriendlyName)). Safe to eject and boot!" 100
        return $savedPdfPath
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

    $defaultIso = if ($InitialIso) { $InitialIso } else {
        $iso26 = Find-DefaultFile 'ubuntu-26.04*-live-server-amd64.iso'
        if ($iso26) { $iso26 } else { Find-DefaultFile 'ubuntu-24.04*-live-server-amd64.iso' }
    }
    $defaultBundle = if ($InitialBundle) { $InitialBundle } else { Find-DefaultFile 'oscar-*-ubuntu-x86_64-offline-full.zip' }
    $defaultPubKey = ''
    $sshDir = Join-Path $HOME '.ssh'
    if (Test-Path -LiteralPath $sshDir -PathType Container) {
        $foundPub = Get-ChildItem -LiteralPath $sshDir -Filter '*.pub' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundPub) { $defaultPubKey = $foundPub.FullName }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'OSCAR Bare-Metal Ubuntu 24.04 / 26.04 LTS Offline Autoinstall USB Creator'
    $form.ClientSize = New-Object System.Drawing.Size(760, 868)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblBanner = New-Object System.Windows.Forms.Label
    $lblBanner.Text = 'Build a UEFI Secure-Boot Ubuntu Server 24.04 / 26.04 LTS + Air-Gapped OSCAR Autoinstall USB Drive'
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

    # 7. Printable Technician Handover One-Sheet PDF (Local Workstation Only)
    $chkOneSheet = New-Object System.Windows.Forms.CheckBox
    $chkOneSheet.Text = '7. Save printable Technician Handover One-Sheet PDF locally (NEVER written to USB):'
    $chkOneSheet.Checked = $true
    $chkOneSheet.Location = New-Object System.Drawing.Point(16, 622)
    $chkOneSheet.Size = New-Object System.Drawing.Size(610, 22)
    $form.Controls.Add($chkOneSheet)

    $txtOneSheet = New-Object System.Windows.Forms.TextBox
    $txtOneSheet.Text = Resolve-DefaultOneSheetPdfPath $InitialHost
    $txtOneSheet.Location = New-Object System.Drawing.Point(16, 646)
    $txtOneSheet.Size = New-Object System.Drawing.Size(610, 24)
    $form.Controls.Add($txtOneSheet)

    $btnOneSheet = New-Object System.Windows.Forms.Button
    $btnOneSheet.Text = 'Save As...'
    $btnOneSheet.Location = New-Object System.Drawing.Point(634, 644)
    $btnOneSheet.Size = New-Object System.Drawing.Size(110, 26)
    $btnOneSheet.Add_Click({
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = 'Save Printable Technician Handover One-Sheet PDF (Local Workstation Only)'
        $dlg.Filter = 'PDF Document (*.pdf)|*.pdf|All Files (*.*)|*.*'
        $dlg.DefaultExt = 'pdf'
        $dlg.FileName = Split-Path -Leaf (Resolve-DefaultOneSheetPdfPath ($txtHost.Text.Trim()))
        if ($dlg.ShowDialog() -eq 'OK') { $txtOneSheet.Text = $dlg.FileName }
    })
    $form.Controls.Add($btnOneSheet)

    $chkOneSheet.Add_CheckedChanged({
        $txtOneSheet.Enabled = $chkOneSheet.Checked
        $btnOneSheet.Enabled = $chkOneSheet.Checked
    })

    # 8. Destructive Confirmation & Action Bar
    $lblConfirm = New-Object System.Windows.Forms.Label
    $lblConfirm.Text = 'Type ERASE-USB to unlock:'
    $lblConfirm.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $lblConfirm.Location = New-Object System.Drawing.Point(16, 684)
    $lblConfirm.Size = New-Object System.Drawing.Size(175, 22)
    $form.Controls.Add($lblConfirm)

    $txtConfirm = New-Object System.Windows.Forms.TextBox
    $txtConfirm.Location = New-Object System.Drawing.Point(195, 682)
    $txtConfirm.Size = New-Object System.Drawing.Size(130, 24)
    $form.Controls.Add($txtConfirm)

    $btnBuild = New-Object System.Windows.Forms.Button
    $btnBuild.Text = 'Create Bootable Autoinstall USB'
    $btnBuild.Font = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    $btnBuild.Enabled = $false
    $btnBuild.Location = New-Object System.Drawing.Point(340, 678)
    $btnBuild.Size = New-Object System.Drawing.Size(286, 32)
    $form.Controls.Add($btnBuild)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(634, 678)
    $btnClose.Size = New-Object System.Drawing.Size(110, 32)
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Location = New-Object System.Drawing.Point(16, 718)
    $progressBar.Size = New-Object System.Drawing.Size(728, 18)
    $form.Controls.Add($progressBar)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
    $txtLog.Location = New-Object System.Drawing.Point(16, 742)
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
            $savedPdf = Invoke-BuildAutoinstallUsb `
                -TargetDiskNumber $chosenDisk.DiskNumber `
                -UbuntuIso $txtIso.Text.Trim('" ') `
                -BundleZip $txtBundle.Text.Trim('" ') `
                -HostVal $txtHost.Text.Trim() `
                -UserVal $txtUser.Text.Trim() `
                -PassHash $pwHashVal `
                -LinuxPasswordPlain $txtPw1.Text `
                -LuksPass $luksVal `
                -ReqSudoPw $reqSudo `
                -KeysOnly ([bool]$chkKeysOnly.Checked) `
                -AuthorizedKeys $authKeys `
                -OscarWebPassHash $oscarWebHashVal `
                -OscarWebPasswordPlain $txtOPw1.Text `
                -PreconfiguredLanesFile $txtLanes.Text.Trim('" ') `
                -AutoInitFirstBoot ([bool]$chkAutoInit.Checked) `
                -SeedDir $txtSeed.Text.Trim('" ') `
                -ExtraSeedFiles @() `
                -OneSheetPdfOutPath $txtOneSheet.Text.Trim('" ') `
                -SkipOneSheetPdf (-not $chkOneSheet.Checked) `
                -Logger $guiLogger
            $txtConfirm.Text = ''
            if ($savedPdf -and (Test-Path -LiteralPath $savedPdf -PathType Leaf)) {
                $openChoice = [System.Windows.Forms.MessageBox]::Show(
                    "Autoinstall USB created and verified on Disk $($chosenDisk.DiskNumber) ($($chosenDisk.FriendlyName)).`n`nPrintable Technician Handover One-Sheet PDF saved locally (NEVER written to USB):`n$savedPdf`n`nOpen the One-Sheet PDF now to print for site handover?",
                    'OSCAR Autoinstall USB Ready', 'YesNo', 'Information')
                if ($openChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Start-Process -FilePath $savedPdf | Out-Null
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Autoinstall USB created and verified on Disk $($chosenDisk.DiskNumber) ($($chosenDisk.FriendlyName)).`n`nSafe to eject and boot on the target x86-64 machine.",
                    'OSCAR Autoinstall USB Ready', 'OK', 'Information') | Out-Null
            }
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

$linuxPwForSheet = ''
if ($PasswordFile) {
    if (-not (Test-Path -LiteralPath $PasswordFile -PathType Leaf)) {
        throw "Password file not found: $PasswordFile"
    }
    $plainFromFile = ([IO.File]::ReadAllLines($PasswordFile)[0]).TrimEnd([char[]]@([char]13, [char]10))
    if (-not $plainFromFile) {
        throw "Password file is empty: $PasswordFile"
    }
    $PasswordHash = [OscarSha512Crypt]::Crypt($plainFromFile, '')
    if (-not $NoOneSheetPdf) { $linuxPwForSheet = $plainFromFile }
    $plainFromFile = ''
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

$oscarWebPwForSheet = ''
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
        if (-not $NoOneSheetPdf) { $oscarWebPwForSheet = $opwFromFile }
    }
    $opwFromFile = ''
} elseif ($OscarAdminPassword) {
    if ($OscarAdminPassword.Length -lt 14) {
        throw 'Initial OSCAR Web administrator password must contain at least 14 characters.'
    }
    $OscarAdminPasswordHash = [OscarSha512Crypt]::Pbkdf2Credential($OscarAdminPassword)
    if (-not $NoOneSheetPdf) { $oscarWebPwForSheet = $OscarAdminPassword }
    $OscarAdminPassword = ''
} elseif ($OscarAdminPasswordHash -and -not $OscarAdminPasswordHash.StartsWith('# PBKDF2_PREENCODED:')) {
    if (-not $OscarAdminPasswordHash.StartsWith('PBKDF2WithHmacSHA1:')) {
        throw '-OscarAdminPasswordHash must start with PBKDF2WithHmacSHA1: or # PBKDF2_PREENCODED:.'
    }
    $OscarAdminPasswordHash = "# PBKDF2_PREENCODED:$OscarAdminPasswordHash"
}

# Offline unit-test mode: render Technician Handover One-Sheet PDF cleanly without touching disks
if ($RenderOneSheetPdfOnly) {
    $previewSha = ''
    if ($OfflineBundlePath -and (Test-Path -LiteralPath $OfflineBundlePath -PathType Leaf)) {
        $previewSha = (Get-FileHash -LiteralPath $OfflineBundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $savedPreview = New-TechnicianOneSheetPdf `
        -OutputPath $RenderOneSheetPdfOnly `
        -HostVal $Hostname `
        -UserVal $Username `
        -LinuxPasswordPlain $linuxPwForSheet `
        -LinuxPasswordHashedOnly ([bool]($PasswordHash -and -not $linuxPwForSheet)) `
        -ReqSudoPw ([bool]$RequireSudoPassword) `
        -LuksPass $luksPassphrase `
        -KeysOnly ([bool]$SshKeysOnly) `
        -AuthorizedKeys $resolvedSshKeys.ToArray() `
        -OscarWebPasswordPlain $oscarWebPwForSheet `
        -OscarWebPasswordHashedOnly ([bool]($OscarAdminPasswordHash -and -not $oscarWebPwForSheet)) `
        -AutoInitFirstBoot ([bool]$AutoInitOscar) `
        -UbuntuIso $IsoPath `
        -BundleZip $OfflineBundlePath `
        -BundleSha256 $previewSha `
        -PreconfiguredLanesFile $LanesFile `
        -SeedDir $SeedDirectory `
        -ExtraSeedFiles $SeedFile `
        -TargetDesc 'Preview / Dry-Run' `
        -BundledManuals @()
    $linuxPwForSheet = ''; $oscarWebPwForSheet = ''; $luksPassphrase = ''
    Write-Host "Rendered Technician Handover One-Sheet PDF to $savedPreview"
    exit 0
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
    $defaultIso = Find-DefaultFile 'ubuntu-26.04*-live-server-amd64.iso'
    if (-not $defaultIso) { $defaultIso = Find-DefaultFile 'ubuntu-24.04*-live-server-amd64.iso' }
    $promptIso = if ($defaultIso) { "Path to ubuntu-26.04.x/24.04.x-live-server-amd64.iso [$defaultIso]" } else { 'Path to ubuntu-26.04.x/24.04.x-live-server-amd64.iso' }
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
            if (-not $NoOneSheetPdf) { $linuxPwForSheet = $plainPw1 }
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
            if (-not $NoOneSheetPdf) { $oscarWebPwForSheet = $plainOPw1 }
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

$savedCliPdf = Invoke-BuildAutoinstallUsb `
    -TargetDiskNumber $DiskNumber `
    -UbuntuIso $IsoPath `
    -BundleZip $OfflineBundlePath `
    -HostVal $Hostname `
    -UserVal $Username `
    -PassHash $PasswordHash `
    -LinuxPasswordPlain $linuxPwForSheet `
    -LuksPass $luksPassphrase `
    -ReqSudoPw ([bool]$RequireSudoPassword) `
    -KeysOnly ([bool]$SshKeysOnly) `
    -AuthorizedKeys $resolvedSshKeys.ToArray() `
    -OscarWebPassHash $OscarAdminPasswordHash `
    -OscarWebPasswordPlain $oscarWebPwForSheet `
    -PreconfiguredLanesFile $LanesFile `
    -AutoInitFirstBoot ([bool]$AutoInitOscar) `
    -SeedDir $SeedDirectory `
    -ExtraSeedFiles $SeedFile `
    -OneSheetPdfOutPath $OneSheetPdfPath `
    -SkipOneSheetPdf ([bool]$NoOneSheetPdf) `
    -Logger $null
$linuxPwForSheet = ''; $oscarWebPwForSheet = ''; $luksPassphrase = ''
if ($savedCliPdf -and (Test-Path -LiteralPath $savedCliPdf -PathType Leaf)) {
    Write-Host "Print this Technician Handover One-Sheet PDF for site handover and securely delete the digital copy afterwards: $savedCliPdf" -ForegroundColor Yellow
}
