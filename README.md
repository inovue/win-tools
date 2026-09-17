# win-tools

Windows PC 向けの、普段使いの便利ツール集です。

## ツール一覧

| ツール | 説明 |
|---|---|
| [画像リサイズ](./Resize-Images.cmd) | フォルダ内の画像を、選んだサイズにまとめて縮小する |

## 前提

- Windows 10 / 11
- 初回のみ、ImageMagick の導入確認が出ることがあります（画面の指示に従ってください）

## 画像リサイズ（Resize-Images）

フォルダ直下の JPEG / PNG / WebP / GIF / BMP / TIFF を、長辺が指定ピクセルに収まるよう縮小します。結果は `1200` のようなサイズ名フォルダへ保存されます。

必要なファイルは **`Resize-Images.cmd` だけ** です。

### 使い方

1. [win-tools の GitHub](https://github.com/inovue/win-tools) を開き、**Code** → **Download ZIP**
2. ZIP を展開し、`Resize-Images.cmd` を「リサイズしたい画像があるフォルダ」へコピー
3. `Resize-Images.cmd` を右クリック → **プロパティ** → **ブロックの解除** にチェック → **OK**  
   （表示されない場合はそのまま次へ）
4. **`Resize-Images.cmd` をダブルクリック**
5. メニューでサイズと品質を選んで実行

終わると「続行するには何かキーを押してください…」と出るので、キーを押して閉じてください。

### うまくいかないとき

| 症状 | 対処 |
|---|---|
| 「Windows によって PC が保護されました」 | **詳細情報** → **実行** |
| プロパティに「ブロックの解除」がある | チェックを入れてから再実行 |
| 対象画像がありません | 画像をフォルダの直下に置く（サブフォルダは対象外） |

### コマンドライン（上級者向け）

```text
Resize-Images.cmd -Help
Resize-Images.cmd -NonInteractive -MaxSize 1200 -Quality 85
Resize-Images.cmd -Path "D:\photos" -NonInteractive -MaxSize 1200 -Quality 85
Resize-Images.cmd -InPlace -Backup -NonInteractive -MaxSize 1200 -Quality 85
```

| 主なオプション | 意味 |
|---|---|
| `-Path <dir>` | 対象フォルダ（省略時は `.cmd` のあるフォルダ） |
| `-MaxSize <px>` | 長辺の最大ピクセル（非対話時は必須） |
| `-Quality <1-100>` | JPEG 品質（省略時 85） |
| `-NonInteractive` | メニュー・確認なし |
| `-InPlace` | 元ファイルを上書き |
| `-Backup` | `-InPlace` 時、`originals\` に退避してから上書き |

## ライセンス

特に指定がない限り、個人利用・改変は自由です。公開・再利用する場合は出典を残してもらえると嬉しいです。
