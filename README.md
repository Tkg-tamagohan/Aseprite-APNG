# Aseprite-APNG

Aseprite で作成したスプライトを、アニメーション PNG（APNG）として直接保存できるようにする拡張機能。

## 機能

- 「Save As」「Save Copy As」で拡張子 `.apng` を選ぶと、開いているスプライトの全フレームをアニメーションつきの PNG として保存する。
- 各フレームは全レイヤーを合成したキャンバス全面の画像として書き出す。
- フレームごとの表示時間（Frame duration）をそのまま反映する。
- ループは無限ループ固定。
- ffmpeg や apngasm などの外部プロセス、外部 Lua ライブラリには依存しない（純Lua実装）。

## 要求バージョン

Aseprite **v1.3.18 以降**が必要。

本拡張が使う `plugin:newFileFormat` API は Aseprite v1.3.18 で安定版に入った。
それより古いバージョンでは動作しない。

## 導入方法

1. [Releases](https://github.com/Tkg-tamagohan/Aseprite-APNG/releases) から最新の `aseprite-apng-v*.aseprite-extension` をダウンロードする。
2. ダウンロードしたファイルをダブルクリックするか、Aseprite の Edit > Preferences > Extensions > Add Extension からファイルを選択する。
3. インストール後、スプライトを開いて File > Save As（または Save Copy As）を選び、拡張子を `.apng` にして保存する。

## 既知の制約

- 書き出しのみ対応。`.apng` ファイルを開いて読み込むことはできない。
- 常に全フレームが書き出し対象になる。タグや範囲でフレームを絞り込む機能はない。
- ループ回数は無限ループ固定で、回数を指定できない。
- 全フレームが同一サイズ・同一カラー形式であることが前提。

## ソースからのビルド

リポジトリをクローンして `build.sh` を実行すると、`dist/` に拡張パッケージが生成される。

```sh
sh build.sh
```

## 開発者向け

APNG の組み立てロジックは `apng.lua` に純Luaモジュールとして切り出してあり、Aseprite なしでスタンドアロンの Lua 5.3 でテストできる。

```sh
lua5.3 tests/test_apng.lua
lua5.3 tests/test_main.lua
```

リリース作業の手順は `docs/release-procedure.md` を参照。
要件定義と仕様上の判断は `docs/` 以下の文書を参照。
