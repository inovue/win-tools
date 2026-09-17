@echo off
setlocal EnableExtensions
REM Single-file GUI launcher (PowerShell embedded below).
set "RESIZE_IMAGES_GUI=1"
REM Default target dir = folder containing this .cmd (overridable via -Path).
REM Do NOT pass -Path here: user -Path in %* would bind twice and fail.
set "RESIZE_IMAGES_ROOT=%~dp0."
set "TMPPS1=%TEMP%\Resize-Images-%RANDOM%%RANDOM%.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$a=Get-Content -LiteralPath '%~f0' -Encoding UTF8; $n=-1; for($i=0;$i -lt $a.Count;$i++){ if($a[$i] -eq '# >>>BEGIN_PS1>>>'){ $n=$i+1; break } }; if($n -lt 0){ throw 'embedded script not found' }; Set-Content -LiteralPath $env:TMPPS1 -Value $a[$n..($a.Length-1)] -Encoding UTF8"
if errorlevel 1 (
  echo Failed to extract embedded script.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TMPPS1%" %*
set "EC=%ERRORLEVEL%"
del /f /q "%TMPPS1%" >nul 2>&1
echo.
if not "%EC%"=="0" echo Exit code: %EC%
pause
exit /b %EC%

# >>>BEGIN_PS1>>>
<#
.SYNOPSIS
  フォルダ内の画像を、指定ピクセルに収まるようリサイズする。

.DESCRIPTION
  既定は対話モード。MaxSize / Quality をメニューで選ぶ（または任意入力）。
  出力はサイズ名フォルダ（例: 1200）へ保存。ImageMagick が無ければ winget で導入。

.EXAMPLE
  .\Resize-Images.cmd
  .\Resize-Images.cmd -Help
  .\Resize-Images.cmd -NonInteractive -MaxSize 1200 -Quality 85
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
param(
  [Alias("h")]
  [switch]$Help,

  [string]$Path = "",

  # 0 = 対話で聞く / 1以上 = そのサイズを使用
  [ValidateRange(0, 20000)]
  [int]$MaxSize = 0,

  # 0 = 対話で聞く（非対話の既定は 85）
  [ValidateRange(0, 100)]
  [int]$Quality = 0,

  [string]$OutputDir = "",

  [switch]$InPlace,

  [switch]$Backup,

  [switch]$NonInteractive,

  [switch]$SkipSetup,

  [string]$WingetPackageId = "ImageMagick.ImageMagick"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Help {
  @"

Resize-Images.cmd - 画像を長辺 MaxSize に収まるようリサイズ

使い方:
  .\Resize-Images.cmd                          対話モード（既定）
  .\Resize-Images.cmd -Help                    このヘルプ
  .\Resize-Images.cmd -NonInteractive -MaxSize 1200 [-Quality 85]

オプション:
  -Help, -h              ヘルプを表示して終了
  -Path <dir>            対象フォルダ（既定: スクリプトの場所）
  -MaxSize <px>          長辺の最大ピクセル（0=対話で選択）
  -Quality <1-100>       JPEG 品質（0=対話で選択 / 非対話既定 85）
  -OutputDir <dir>       出力先（未指定なら .\MaxSize\ ）
  -InPlace               元ファイルを上書き（一時ファイル経由で安全に書き込み）
  -Backup                -InPlace 時、originals\ に退避してから上書き
  -NonInteractive        メニュー・確認なし（-MaxSize 必須）
  -SkipSetup             ImageMagick の自動インストールをスキップ
  -WingetPackageId       winget パッケージ ID
  -WhatIf                実行内容のプレビューのみ

対話モードの流れ:
  1) 最大サイズ選択（640〜2560 または任意）
  2) 品質選択（60〜95 または任意）
  3) 確認後、{MaxSize}\ フォルダへ出力

例:
  .\Resize-Images.cmd
  .\Resize-Images.cmd -MaxSize 1200
  .\Resize-Images.cmd -MaxSize 800 -Quality 90
  .\Resize-Images.cmd -NonInteractive -MaxSize 1920 -Quality 85
  .\Resize-Images.cmd -InPlace -Backup -MaxSize 1200 -Quality 85 -NonInteractive

"@ | Write-Host
}

function Test-NativeSuccess {
  # ネイティブコマンド直後の exit code。未設定は成功扱い
  if ($null -eq $global:LASTEXITCODE) { return $true }
  return ($global:LASTEXITCODE -eq 0)
}

function ConvertTo-MagickPath {
  param([Parameter(Mandatory = $true)][string]$PathValue)
  # ImageMagick は \ をエスケープ扱いすることがあるため / に正規化
  return ([System.IO.Path]::GetFullPath($PathValue) -replace '\\', '/')
}

function Invoke-NativeMagick {
  param(
    [Parameter(Mandatory = $true)][string]$MagickExe,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  # stderr を ErrorAction Stop で例外化させない
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $global:LASTEXITCODE = 0
  try {
    $output = & $MagickExe @Arguments 2>&1
    $code = $global:LASTEXITCODE
    return [pscustomobject]@{
      ExitCode = $(if ($null -eq $code) { 0 } else { [int]$code })
      Output   = $output
    }
  } finally {
    $ErrorActionPreference = $prev
  }
}

function Get-ImageSize {
  param(
    [Parameter(Mandatory = $true)][string]$MagickExe,
    [Parameter(Mandatory = $true)][string]$FilePath
  )
  $mp = ConvertTo-MagickPath -PathValue $FilePath
  # [0] = first frame only. Without it, multi-frame GIF/TIFF concatenate
  # "%w %h" per frame (e.g. "80 8080 80") and height is misread.
  $result = Invoke-NativeMagick -MagickExe $MagickExe -Arguments @(
    "identify", "-ping", "-format", "%w %h", "${mp}[0]"
  )
  if ($result.ExitCode -ne 0) {
    throw "identify 失敗 (exit=$($result.ExitCode)): $($result.Output)"
  }
  $line = (($result.Output | Out-String).Trim() -split "[\r\n]+" |
    Where-Object { $_ -match '^\d+\s+\d+$' } |
    Select-Object -First 1)
  if (-not $line) {
    throw "サイズ取得失敗: $($result.Output)"
  }
  $m = [regex]::Match($line, '^(\d+)\s+(\d+)$')
  if (-not $m.Success) {
    throw "サイズ解析失敗: $line"
  }
  return @{
    Width  = [int]$m.Groups[1].Value
    Height = [int]$m.Groups[2].Value
  }
}

function Invoke-MagickResize {
  param(
    [Parameter(Mandatory = $true)][string]$MagickExe,
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$Geometry,
    [Parameter(Mandatory = $true)][int]$JpegQuality
  )

  $destDir = Split-Path -Parent $Destination
  if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  }

  # 同一パス上書きでも壊れないよう、必ず一時ファイル経由
  $ext = [System.IO.Path]::GetExtension($Destination)
  if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".jpg" }
  $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("resize-{0}{1}" -f [guid]::NewGuid().ToString("N"), $ext)

  try {
    $src = ConvertTo-MagickPath -PathValue $Source
    $tmp = ConvertTo-MagickPath -PathValue $temp
    $result = Invoke-NativeMagick -MagickExe $MagickExe -Arguments @(
      $src, "-auto-orient", "-resize", $Geometry, "-strip", "-quality", "$JpegQuality", $tmp
    )
    if ($result.ExitCode -ne 0) {
      throw "magick 失敗 (exit=$($result.ExitCode)): $($result.Output)"
    }
    if (-not (Test-Path -LiteralPath $temp)) {
      throw "一時ファイルが作成されませんでした: $($result.Output)"
    }
    Move-Item -LiteralPath $temp -Destination $Destination -Force
  } finally {
    if (Test-Path -LiteralPath $temp) {
      Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
  }
}

function Refresh-Path {
  $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $user = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($null -eq $machine) { $machine = "" }
  if ($null -eq $user) { $user = "" }
  $env:Path = "$machine;$user"
}

function Find-Magick {
  Refresh-Path
  $cmd = Get-Command magick -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }

  $patterns = @()
  if ($env:ProgramFiles) {
    $patterns += (Join-Path $env:ProgramFiles "ImageMagick*\magick.exe")
  }
  if (${env:ProgramFiles(x86)}) {
    $patterns += (Join-Path ${env:ProgramFiles(x86)} "ImageMagick*\magick.exe")
  }

  foreach ($pattern in $patterns) {
    $hit = Get-Item -Path $pattern -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}

function Ensure-ImageMagick {
  param([string]$PackageId)

  $magick = Find-Magick
  if ($magick) {
    Write-Host "ImageMagick OK: $magick"
    return $magick
  }

  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget が見つかりません。Microsoft Store から App Installer を入れてください。"
  }

  Write-Host "ImageMagick が見つからないため winget でインストールします: $PackageId"
  $wingetArgs = @(
    "install", "--id", $PackageId,
    "-e", "--accept-package-agreements", "--accept-source-agreements"
  )
  & winget @wingetArgs
  $code = $global:LASTEXITCODE

  # 0=成功 / -1978335189=既にインストール済 など
  $okCodes = @(0, -1978335189, -1978335135)
  if ($okCodes -notcontains $code) {
    # インストール後に見つかれば続行
    $magick = Find-Magick
    if ($magick) {
      Write-Host "winget exit=$code だが magick を検出したため続行: $magick"
      return $magick
    }
    throw "winget install が失敗しました (exit=$code)。管理者権限や UAC を確認してください。"
  }

  Start-Sleep -Seconds 1
  $magick = Find-Magick
  if (-not $magick) {
    throw "インストール後も magick.exe が見つかりません。新しい PowerShell を開き直して再実行してください。"
  }
  Write-Host "ImageMagick インストール完了: $magick"
  return $magick
}

function Read-MaxSizeInteractive {
  $presets = @(640, 800, 1024, 1200, 1600, 1920, 2048, 2560)

  Write-Host ""
  Write-Host "========================================"
  Write-Host "  1/2  最大サイズを選択"
  Write-Host "  (長辺がこの値に収まるよう縮小)"
  Write-Host "========================================"
  Write-Host ""

  for ($i = 0; $i -lt $presets.Count; $i++) {
    $n = $i + 1
    $label = switch ($presets[$i]) {
      640  { "サムネイル向き" }
      800  { "Web小さめ" }
      1024 { "Web標準" }
      1200 { "Web / SNS よく使う" }
      1600 { "高解像度Web" }
      1920 { "フルHD幅" }
      2048 { "高詳細" }
      2560 { "WQHD幅" }
      default { "" }
    }
    if ($label) {
      Write-Host ("  [{0}]  {1,5} px  - {2}" -f $n, $presets[$i], $label)
    } else {
      Write-Host ("  [{0}]  {1,5} px" -f $n, $presets[$i])
    }
  }
  Write-Host ("  [{0}]  自分で入力" -f ($presets.Count + 1))
  Write-Host "  [H]  ヘルプ"
  Write-Host "  [Q]  キャンセル"
  Write-Host ""

  while ($true) {
    $choice = Read-Host "番号を入力 (Enter=1200px)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
      return 1200
    }
    if ($choice -match '^[Qq]$') {
      Write-Host "キャンセルしました。"
      exit 0
    }
    if ($choice -match '^[Hh]$') {
      Show-Help
      continue
    }
    if ($choice -match '^\d+$') {
      $num = [int]$choice
      if ($num -ge 1 -and $num -le $presets.Count) {
        return [int]$presets[$num - 1]
      }
      if ($num -eq ($presets.Count + 1)) {
        while ($true) {
          $custom = Read-Host "最大サイズ (px) を入力 (1-20000)"
          if ($custom -match '^\d+$') {
            $px = [int]$custom
            if ($px -ge 1 -and $px -le 20000) {
              return $px
            }
          }
          Write-Host "  1〜20000 の整数を入力してください。" -ForegroundColor Yellow
        }
      }
    }
    Write-Host "  有効な番号を入力してください。" -ForegroundColor Yellow
  }
}

function Read-QualityInteractive {
  $presets = @(
    @{ Q = 60; Label = "小さめファイル（やや粗い）" }
    @{ Q = 70; Label = "軽量Web" }
    @{ Q = 75; Label = "バランス寄り軽量" }
    @{ Q = 85; Label = "おすすめ（品質と容量のバランス）" }
    @{ Q = 90; Label = "高品質" }
    @{ Q = 95; Label = "ほぼ劣化なし（ファイル大）" }
  )

  Write-Host ""
  Write-Host "========================================"
  Write-Host "  2/2  JPEG 品質を選択"
  Write-Host "========================================"
  Write-Host ""

  for ($i = 0; $i -lt $presets.Count; $i++) {
    $n = $i + 1
    Write-Host ("  [{0}]  Quality {1,2}  - {2}" -f $n, $presets[$i].Q, $presets[$i].Label)
  }
  Write-Host ("  [{0}]  自分で入力 (1-100)" -f ($presets.Count + 1))
  Write-Host "  [H]  ヘルプ"
  Write-Host "  [Q]  キャンセル"
  Write-Host ""

  while ($true) {
    $choice = Read-Host "番号を入力 (Enter=85)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
      return 85
    }
    if ($choice -match '^[Qq]$') {
      Write-Host "キャンセルしました。"
      exit 0
    }
    if ($choice -match '^[Hh]$') {
      Show-Help
      continue
    }
    if ($choice -match '^\d+$') {
      $num = [int]$choice
      if ($num -ge 1 -and $num -le $presets.Count) {
        return [int]$presets[$num - 1].Q
      }
      if ($num -eq ($presets.Count + 1)) {
        while ($true) {
          $custom = Read-Host "品質 (1-100) を入力"
          if ($custom -match '^\d+$') {
            $q = [int]$custom
            if ($q -ge 1 -and $q -le 100) {
              return $q
            }
          }
          Write-Host "  1〜100 の整数を入力してください。" -ForegroundColor Yellow
        }
      }
    }
    Write-Host "  有効な番号を入力してください。" -ForegroundColor Yellow
  }
}

function Confirm-Go {
  param(
    [int]$Size,
    [int]$JpegQuality,
    [int]$Count,
    [string]$Dest,
    [bool]$Overwrite,
    [int]$ExistingOutputs = 0
  )
  Write-Host ""
  Write-Host "---- 確認 ----"
  Write-Host ("  対象枚数 : {0}" -f $Count)
  Write-Host ("  最大サイズ: {0} px (長辺)" -f $Size)
  Write-Host ("  品質     : {0}" -f $JpegQuality)
  if ($Overwrite) {
    Write-Host "  出力先  : 上書き (InPlace)"
  } else {
    Write-Host ("  出力先  : {0}" -f $Dest)
    if ($ExistingOutputs -gt 0) {
      Write-Host ("  注意    : 出力先に既存ファイルが {0} 件あります（上書きされます）" -f $ExistingOutputs) -ForegroundColor Yellow
    }
  }
  Write-Host ""
  $ans = Read-Host "この内容で実行しますか？ [Y/n]"
  if ($ans -match '^[Nn]') {
    Write-Host "キャンセルしました。"
    exit 0
  }
}

function Get-RootImageFiles {
  param([Parameter(Mandatory = $true)][string]$Dir)
  # パイプライン出力。呼び出し側で必ず $files = @(Get-RootImageFiles ...) とする
  Get-ChildItem -LiteralPath $Dir -File -ErrorAction Stop |
    Where-Object {
      $_.Extension -match '^\.(jpe?g|png|webp|gif|bmp|tiff?)$' -and
      $_.Name -notmatch '^\.'
    } |
    Sort-Object Name
}

# ----- main -----
if ($Help) {
  Show-Help
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Path)) {
  # Launcher sets RESIZE_IMAGES_ROOT to the .cmd folder (extracted .ps1 lives in %TEMP%).
  if (-not [string]::IsNullOrWhiteSpace($env:RESIZE_IMAGES_ROOT)) {
    $Path = $env:RESIZE_IMAGES_ROOT
  } elseif ($PSScriptRoot) {
    $Path = $PSScriptRoot
  } else {
    $Path = (Get-Location).Path
  }
}

if (-not (Test-Path -LiteralPath $Path)) {
  throw "対象パスが存在しません: $Path"
}
$PathItem = Get-Item -LiteralPath $Path
if (-not $PathItem.PSIsContainer) {
  throw "対象パスはフォルダである必要があります: $Path"
}
$root = $PathItem.FullName

$sizeWasSet = $PSBoundParameters.ContainsKey("MaxSize") -and ($MaxSize -gt 0)
$qualityWasSet = $PSBoundParameters.ContainsKey("Quality") -and ($Quality -gt 0)
$isInteractive = -not $NonInteractive.IsPresent

if ($Backup -and -not $InPlace) {
  Write-Warning "-Backup は -InPlace と併用時のみ有効です。無視します。"
}
if ($InPlace -and -not [string]::IsNullOrWhiteSpace($OutputDir)) {
  Write-Warning "-InPlace 指定時は -OutputDir を無視します。"
}

# 画像が無いならメニュー前に終了（空フォルダで余計な質問をしない）
$files = @(Get-RootImageFiles -Dir $root)
if ($files.Count -eq 0) {
  Write-Warning "対象画像がありません（フォルダ直下のみ対象）: $root"
  exit 0
}
Write-Host ("対象画像: {0} 枚" -f $files.Count)

if ($isInteractive) {
  try {
    if ([Console]::IsInputRedirected) {
      throw "対話入力ができません（stdin がリダイレクトされています）。-NonInteractive -MaxSize <px> を指定してください。"
    }
  } catch [System.IO.IOException] {
    throw "対話入力ができません。-NonInteractive -MaxSize <px> を指定してください。"
  }
}

# --- size / quality（確認前に決定。フォルダはまだ作らない）---
if ($isInteractive) {
  if (-not $sizeWasSet) {
    $MaxSize = Read-MaxSizeInteractive
  }
  if (-not $qualityWasSet) {
    $Quality = Read-QualityInteractive
  }
} else {
  if ($MaxSize -le 0) {
    throw "非対話モードでは -MaxSize に 1 以上を指定してください。ヘルプ: .\Resize-Images.cmd -Help"
  }
  if ($Quality -le 0) {
    $Quality = 85
  }
}

if ($MaxSize -lt 1 -or $MaxSize -gt 20000) {
  throw "-MaxSize は 1〜20000 で指定してください。"
}
if ($Quality -lt 1 -or $Quality -gt 100) {
  throw "-Quality は 1〜100 で指定してください。"
}

# --- 出力先パス決定（作成は確認後）---
if ($InPlace) {
  $destRoot = $root
} elseif ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $destRoot = Join-Path $root "$MaxSize"
} elseif ([System.IO.Path]::IsPathRooted($OutputDir)) {
  $destRoot = $OutputDir
} else {
  $destRoot = Join-Path $root $OutputDir
}
$destRoot = [System.IO.Path]::GetFullPath($destRoot)

if (-not $InPlace) {
  if ([string]::Equals($destRoot, $root, [StringComparison]::OrdinalIgnoreCase)) {
    throw "出力先が入力フォルダと同じです。-OutputDir を別にするか、-InPlace を使ってください。"
  }
}

$existingOutputs = 0
if (-not $InPlace -and (Test-Path -LiteralPath $destRoot)) {
  $existingOutputs = @(@(Get-ChildItem -LiteralPath $destRoot -File -ErrorAction SilentlyContinue)).Count
}

if ($isInteractive) {
  Confirm-Go -Size $MaxSize -JpegQuality $Quality -Count $files.Count -Dest $destRoot -Overwrite:$InPlace.IsPresent -ExistingOutputs $existingOutputs
}

# --- setup（確認後にインストール／出力フォルダ作成）---
if ($SkipSetup) {
  $magickExe = Find-Magick
  if (-not $magickExe) { throw "magick が見つかりません。-SkipSetup を外して再実行してください。" }
} else {
  $magickExe = Ensure-ImageMagick -PackageId $WingetPackageId
}

if (-not $InPlace) {
  if ($PSCmdlet.ShouldProcess($destRoot, "create output directory")) {
    New-Item -ItemType Directory -Force -Path $destRoot | Out-Null
  }
}

if ($InPlace -and $Backup) {
  $backupDir = Join-Path $root "originals"
  if ($PSCmdlet.ShouldProcess($backupDir, "create backup directory")) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  }
}

$geometry = "${MaxSize}x${MaxSize}>"
Write-Host ""
Write-Host ("処理開始: {0} 枚 / MaxSize={1}px / Quality={2}" -f $files.Count, $MaxSize, $Quality)
if ($InPlace) {
  Write-Host "出力: 上書き"
} else {
  Write-Host ("出力: {0}" -f $destRoot)
}

$ok = 0
$skip = 0
$fail = 0

foreach ($file in $files) {
  $dest = if ($InPlace) { $file.FullName } else { Join-Path $destRoot $file.Name }

  if (-not $PSCmdlet.ShouldProcess($file.FullName, "resize to fit ${MaxSize}px -> $dest")) {
    continue
  }

  try {
    if ($InPlace -and $Backup) {
      $bak = Join-Path (Join-Path $root "originals") $file.Name
      if (-not (Test-Path -LiteralPath $bak)) {
        Copy-Item -LiteralPath $file.FullName -Destination $bak -Force
      }
    }

    $size = Get-ImageSize -MagickExe $magickExe -FilePath $file.FullName
    $w = $size.Width
    $h = $size.Height
    $needsResize = ($w -gt $MaxSize) -or ($h -gt $MaxSize)

    if (-not $needsResize) {
      if (-not $InPlace) {
        if (-not [string]::Equals($file.FullName, $dest, [StringComparison]::OrdinalIgnoreCase)) {
          Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
        }
      }
      Write-Host ("  SKIP (<={0}px): {1} {2}x{3}" -f $MaxSize, $file.Name, $w, $h)
      $skip++
      continue
    }

    Invoke-MagickResize -MagickExe $magickExe -Source $file.FullName -Destination $dest -Geometry $geometry -JpegQuality $Quality

    $after = Get-ImageSize -MagickExe $magickExe -FilePath $dest
    Write-Host ("  OK: {0} {1}x{2} -> {3}x{4}" -f $file.Name, $w, $h, $after.Width, $after.Height)
    $ok++
  } catch {
    Write-Host ("  FAIL: {0} - {1}" -f $file.Name, $_.Exception.Message) -ForegroundColor Red
    $fail++
  }
}

Write-Host ""
Write-Host ("完了: OK={0} / SKIP={1} / FAIL={2}" -f $ok, $skip, $fail)
if (-not $InPlace) {
  Write-Host ("保存先: {0}" -f $destRoot)
}
if ($fail -gt 0) { exit 1 }
exit 0
