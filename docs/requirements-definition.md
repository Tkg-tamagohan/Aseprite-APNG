# 要件定義書：Aseprite APNG エクスポート拡張

本書は Aseprite 拡張「Aseprite-APNG」の要件を定義する。
確定した仕様上の判断は `docs/decision-records.md` に記録し、本書では表の ID で参照する。
未決事項は各節の TODO として明示し、確定した時点で決定記録へ移す。

## 目的と背景

Aseprite で作成したスプライトを、中間ファイルを経由せず APNG ファイルとして保存できるようにする。

現状 Aseprite 本体は APNG の書き出しに対応していない。
本体へのネイティブ実装は aseprite/aseprite PR #5472 として提案されているが、2026年8月時点でドラフトのまま停滞しているため、拡張での実装に意義がある。

## 用語

- **連番PNG**：Aseprite のエクスポート機能が出力する、フレームごとに分割された PNG ファイル群。本拡張は中間生成物として内部的に扱う。
- **APNG**：Animated PNG。PNG チャンクに acTL・fcTL・fdAT を追加してアニメーションを表現する形式。

## スコープ

### やること

- 拡張子 `apng` のファイル形式を `plugin:newFileFormat` で登録し、「Save As」「Save Copy As」から選択可能にする。
- 保存時に開いているスプライトの全フレームを、キャンバス全面の合成画像として書き出す。
- 外部プロセス・外部ライブラリに依存しない純Lua実装で APNG を組み立てる（仕様決定 B）。

### やらないこと

- APNG の読み込み（`onload` は実装しない）。
- 連番PNGフォルダを選択して変換する独立コマンド（D-1）。初版では Save As 経由のみとする。需要があれば後続フェーズで検討する。

## 機能要件

### 形式登録と保存導線

- `plugin:newFileFormat{ extensions = {"apng"}, onsave = ... }` を `init(plugin)` で登録する。
- `onsave` は `ev.file`（バイナリ書き込みモードのファイルハンドル）へ APNG バイナリを書き込み、成功時 `true` を返す。
- 対象スプライトは `ev.sprite` から取得する（`ev` テーブルに `sprite`・`file`・`filename` が含まれることは Aseprite 本体の実装で確認済み）。フォールバックとして `app.sprite` も参照する。

### フレームのレンダリング

- 各フレームについて、全レイヤーを合成したキャンバス全面の画像を生成する。
- `Image:drawSprite(sprite, frameNumber)` でフレームを描画する。

### 一時PNGの生成

- 各フレーム画像を `Image:saveAs` で一時PNGとして書き出す。
- 一時ファイルは `app.fs.tempPath` 配下に保存ごとに一意な一時ディレクトリを作成して生成し、処理終了時に成否に関わらず削除する。
- 全フレーム同一サイズ・同一カラー形式であることを前提とし、IHDR が一致しない場合はエラーとする。

### APNG の組み立て

- 一時PNG群の IDAT チャンクを抽出し、APNG チャンク構成に詰め替える。
- 構成：PNG シグネチャ、IHDR、acTL、fcTL＋IDAT（先頭フレーム）、fcTL＋fdAT（2フレーム目以降）、IEND。
- 先頭フレームを規格上のデフォルト画像とし、アニメーションに含める。
- dispose op は NONE、blend op は SOURCE とする（各フレームが全面画像のため部分合成は不要）。
- CRC32 はLuaで計算する（string.pack 利用）。

### フレーム時間

- 各フレームの `Frame.duration`（秒）を fcTL の delay_num/delay_den に変換して反映する（仕様決定 E）。
- 変換は delay_den=1000 固定のミリ秒丸めとし、0 になった場合は delay_num=1 に補正する。

### ループ回数

- 無限ループ固定（acTL num_plays=0）。回数指定 UI は後続フェーズ（仕様決定 F）。

### 対象フレーム範囲

- 全フレームを対象とする。タグや範囲選択は後続フェーズ（仕様決定 G）。

## 配布と導入

- `package.json` と Lua スクリプトを zip 化し、拡張子を `.aseprite-extension` に変更して配布する。
- インストールはファイルのダブルクリック、または Edit > Preferences > Extensions > Add Extension。
- リリースは GitHub Releases で行う。

## 実行環境と依存

- 対象環境：Aseprite が動作する OS（Windows 前提で開発・検証する）。
- 要求 Aseprite バージョン：v1.3.18 以降。`newFileFormat` API は PR #5174 として 2026-03-20 に main へマージされ、安定版 v1.3.18 に含まれることを確認済み（仕様決定 H）。
- 外部依存：なし（ffmpeg、apngasm、外部Luaライブラリを使わない）。

## 検証方針

- APNG 組み立てロジックは Aseprite 非依存の純Luaモジュールとして切り出し、スタンドアロンの Lua インタプリタで単体テスト可能にする。
- 生成した APNG はブラウザでの再生表示、および apng 検証ツールでの構造確認で検証する。
- Aseprite 上での統合検証は Windows 実機での手動確認とする（自動化不可）。

## 未決事項一覧

現時点で未決事項はない。新たな論点が出た場合は本節に TODO として追記し、確定後に決定記録へ移す。

## 後続フェーズの検討対象

- ループ回数の指定 UI（仕様決定 F）
- フレーム範囲・タグ選択（仕様決定 G）
- 連番PNGフォルダを選択して変換するコマンド型導線の併設（D-1）

## 参照資料

- Aseprite API ドキュメント：https://aseprite.org/api/（plugin:newFileFormat、Image、Frame.duration など）
- Aseprite ドキュメント：https://aseprite.org/docs/
