#!/bin/sh
# tests/bats/ の .bats を、固定版の bats で実行する入口。
# 検査の中身は持たない。検査は .bats にある。この入口は、引数の検査と、bats の起動と、終了コードの受け渡しだけを行う。
# 使い方: sh tests/lib/run-bats.sh <tests/bats/名前.bats> [unit|smoke|contract]
# 終了コードは bats のものをそのまま返す。bats は前面で動く。入口が TERM を受けても bats へは渡さない（既知のリスク）。
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# Why: mise は、作業ディレクトリの設定から bats の版と実体を解決する。リポジトリの固定版を使うため、リポジトリに移ってから照合する。
cd "$ROOT"

usage() {
  printf '%s\n' '使い方: sh tests/lib/run-bats.sh <tests/bats/名前.bats> [unit|smoke|contract]' >&2
  exit 2
}

# Why: 引数の数とモードの値を、bats を探す前に検査する。不正な呼び出しは、導入の状態に関係なく止まる。
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
fi
file=$1
mode=${2:-}
case "$mode" in
  '' | unit | smoke | contract) ;;
  *) usage ;;
esac
if [ ! -f "$file" ]; then
  printf 'FAIL: 検査のファイルが無い: %s\n' "$file" >&2
  exit 2
fi

# bats の実体と版は、固定版の照合（resolve_tool）で得る。3つの環境変数は resolve-tool.sh の中にある。
# shellcheck source=/dev/null
. "$ROOT/scripts/lib/resolve-tool.sh"
resolve_tool bats 's/^Bats //p' --version || exit 1
bats_bin=$RESOLVED_PATH

# Why: bats は前面で動かす。背景で動かすと、子は SIGINT を無視して始まり、INT の検査（子が 130 で止まること）が通らないため。
# 代わりに、この入口が TERM を受けても bats へは渡さない。入口だけに TERM が届くと、bats は孤児として残る。
# これは利用者が受け入れた既知のリスクである。入口が TERM を受けたときの後始末は無い。
rc=0
if [ -n "$mode" ]; then
  "$bats_bin" --filter-tags "$mode" "$file" || rc=$?
else
  "$bats_bin" "$file" || rc=$?
fi
exit "$rc"
