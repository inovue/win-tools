# win-tools

Windows PC 向けの、普段使いの便利ツール集（PowerShell スクリプト中心）。

## ツール一覧

| スクリプト | 説明 |
|---|---|
| [`Resize-Images.ps1`](./Resize-Images.ps1) | フォルダ内の画像を長辺指定サイズにリサイズ（対話 / 非対話） |

## 前提

- Windows 10 / 11
- PowerShell 5.1 以上（Windows PowerShell または PowerShell 7+）
- 一部ツールは [winget](https://learn.microsoft.com/windows/package-manager/winget/) で依存を自動導入します

## Resize-Images.ps1

フォルダ直下の画像（JPEG / PNG / WebP / GIF / BMP / TIFF）を、長辺が指定ピクセルに収まるよう縮小します。ImageMagick が無ければ winget で導入します。

### 使い方

```powershell
# 対話モード（サイズ・品質をメニューで選択）
.\Resize-Images.ps1

# ヘルプ
.\Resize-Images.ps1 -Help

# 非対話（バッチ向け）
.\Resize-Images.ps1 -NonInteractive -MaxSize 1200 -Quality 85
```

既定では `{MaxSize}` フォルダ（例: `1200\`）へ出力します。元ファイルを上書きする場合は `-InPlace`、退避してから上書きする場合は `-InPlace -Backup` を使います。

## ライセンス

特に指定がない限り、個人利用・改変は自由です。公開・再利用する場合は出典を残してもらえると嬉しいです。
