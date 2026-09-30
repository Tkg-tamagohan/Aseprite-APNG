# 実装計画

要件定義書（`docs/requirements-definition.md`）の確定仕様を実装タスクに分解したもの。
各フェーズはおおむね 1PR に対応する。進捗は本書のチェックリストで管理する。

## 前提と環境

- 言語：Lua 5.3 系（`string.pack` を利用）。
- 純Luaモジュール（APNG 組立ロジック）は Aseprite 非依存で、Linux 上のスタンドアロン Lua でもテストできる。
- Aseprite 連携部分（`plugin:newFileFormat`、`Image:drawSprite`、`Image:saveAs`）は Aseprite 上でのみ動作し、Windows 実機での手動検証が必要。
- `newFileFormat` API は 2026-03-20 に main へマージされた新機能であり、含まれる安定版リリースを実装時に確認する（仕様決定 H）。

## 構成

```
Aseprite-APNG/
  package.json        # 拡張マニフェスト
  main.lua            # init(plugin): newFileFormat 登録、onsave 処理
  apng.lua            # APNG 組立モジュール（純Lua・Aseprite 非依存）
  tests/              # スタンドアロン Lua テスト
  docs/               # 要件定義書・決定記録・本書
```

- `apng.lua`：PNG バイト列のチャンク解析、IDAT→fdAT 詰め替え、acTL/fcTL 生成、CRC32 計算を担う。
- `main.lua`：`Image:drawSprite` で各フレームを全面合成し、`Image:saveAs` で一時PNGを生成、`apng.lua` へ渡す。Aseprite API への依存はこのファイルに閉じ込める。

## フェーズ別タスク

### Phase 1：純Lua APNG 組立モジュール（`apng.lua`）＋ 単体テスト

- [ ] PNG チャンクパーサ（シグネチャ・IHDR・IDAT 抽出）
- [ ] CRC32 計算（string.pack ベース）
- [ ] acTL/fcTL/fdAT 生成と APNG シリアライズ
- [ ] フレーム時間変換（duration 秒 → delay_num/delay_den）
- [ ] スタンドアロン Lua テスト：合成した連番PNG→APNG 変換、構造をバイナリレベルで検証
- [ ] 生成 APNG の再生確認（ブラウザ表示）

受け入れ条件：複数フレーム・異なるフレーム時間の入力で正しい APNG が生成され、ブラウザでアニメーション再生される。

### Phase 2：Aseprite 拡張エントリ（`main.lua`＋`package.json`）

- [ ] `package.json` 作成（contributes.scripts）
- [ ] `plugin:newFileFormat` で `apng` 拡張子登録（onsave のみ）
- [ ] `onsave` 実装：全フレームを `Image:drawSprite` で全面合成 → `Image:saveAs` で一時PNG → `apng.lua` で組立 → ファイルハンドルへ書き込み
- [ ] 一時ファイルの生成・削除（os.tmpname 系）
- [ ] IHDR 不一致・単一フレーム・空スプライトなどのエラーハンドリング
- [ ] `newFileFormat` を含む Aseprite 最小バージョンの確認と記載（仕様決定 H）

受け入れ条件：`.aseprite-extension` として梱包してインストールし、Save As → .apng で APNG が保存される。実機手動検証（Windows 上の Aseprite）。

### Phase 3：配布・ドキュメント

- [ ] `.aseprite-extension` のビルド手順（zip 作成スクリプト or 手順書）
- [ ] README（機能、導入方法、要求バージョン、既知の制約）
- [ ] GitHub Releases への初版アップロード手順

受け入れ条件：README 手順どおりにインストールして利用できる。

## 引き継ぎ手順

- 現在地の確認：本書のチェックリスト（`[x]` 済みフェーズ）を見る。
- ブランチ規約：`devin/<unixtime>-<slug>` でブランチを切り、main へ PR を出す。
- Aseprite が必要な作業：Phase 2 の動作確認は Windows 実機のみ。Linux 環境では Phase 1 の純Luaテストまで検証可能。
