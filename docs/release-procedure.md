# リリース手順

GitHub Releases へ拡張パッケージ（`.aseprite-extension`）を公開する手順。
初版リリースと、以降のバージョン更新リリースで共通の流れとする。

## 前提

- リリースしたい変更がすべて `main` にマージ済みであること。
- `package.json` の `version` をリリースするバージョンに更新済みであること。
  ビルドスクリプトはこの値を成果物のファイル名に使う。
- ローカルの `main` が `origin/main` と一致していること。

## 手順

1. `main` ブランチで最新のコミットを取得する。

   ```sh
   git checkout main && git pull origin main
   ```

2. 拡張パッケージを組み立てる。

   ```sh
   sh build.sh
   ```

   `dist/aseprite-apng-v<version>.aseprite-extension` が生成される。
   `unzip -l` で `package.json`、`main.lua`、`apng.lua`、`LICENSE` の4ファイルがルートに並んでいることを確認する。

3. バージョンに対応するタグを打ってプッシュする。

   ```sh
   git tag v<version> && git push origin v<version>
   ```

4. GitHub Releases を作成し、パッケージを添付する。

   `gh` CLI が使える環境では次のコマンドで作成できる。

   ```sh
   gh release create v<version> \
     dist/aseprite-apng-v<version>.aseprite-extension \
     --title "v<version>" \
     --notes "リリース内容の要約"
   ```

   `--notes` にはそのリリースの説明を書く。
   初版なら「初版リリース」、更新版なら変更点の要約を書き換えて指定する。

   Web UI から作成する場合は、Releases ページで「Draft a new release」を開き、先ほどのタグを選んでタイトルと説明を記入し、生成した `.aseprite-extension` ファイルを Assets にドラッグして公開する。

## 検証

公開後、Releases から `.aseprite-extension` をダウンロードし、README の導入手順どおりに Aseprite へインストールして Save As → `.apng` で保存できることを実機で確認する。
Aseprite 連携の動作確認は Windows 実機での手動検証のみ可能である。

## 補足

`build.sh` は POSIX シェルと `zip` コマンドがあれば動く。
Windows で手作業する場合は、`package.json`、`main.lua`、`apng.lua`、`LICENSE` を zip 化して拡張子を `.aseprite-extension` に変更すれば同等の成果物になる。
