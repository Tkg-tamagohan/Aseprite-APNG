#!/bin/sh
# Aseprite-APNG 拡張パッケージ（.aseprite-extension）を組み立てる。
# package.json の version をファイル名に反映し、dist/ へ出力する。
# 使い方: リポジトリルートで `sh build.sh`
set -eu

cd "$(dirname "$0")"

version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)
if [ -z "$version" ]; then
  echo "error: package.json から version を読み取れません" >&2
  exit 1
fi

name="aseprite-apng-v${version}.aseprite-extension"
mkdir -p dist
out="dist/${name}"
rm -f "$out"

# -j: ディレクトリ階層を捨ててルートに並べる。-X: 余計なファイル属性を付けない。
# LICENSE は MIT の表示条件を配布物で満たすために同梱する。
zip -X -j "$out" package.json main.lua apng.lua LICENSE

echo "created: $out"
