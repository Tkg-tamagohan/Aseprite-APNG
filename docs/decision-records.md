# 決定記録

要件定義に関する確定した判断を記録する。
要件定義書（`docs/requirements-definition.md`）本文中では「仕様決定 X」の形式で参照する。

| ID | 項目 | 決定内容 |
|----|------|----------|
| A | アプリの形式 | Aseprite 拡張（Lua）。配布は `.aseprite-extension` |
| B | エンコード方式 | 純Lua実装。各フレームPNGの IDAT を fdAT へ詰め替えて APNG を組み立てる。外部プロセス・外部ライブラリ不使用 |
| C | UX 導線 | ファイル形式登録型（`plugin:newFileFormat` で `.apng` を登録）。Save As / Save Copy As から直接出力。連番PNGを経由しない |
| D | リポジトリ | Tkg-tamagohan/Aseprite-APNG を使用 |
