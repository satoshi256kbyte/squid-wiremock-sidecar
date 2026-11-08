#!/bin/sh
# tests/bats/ の .bats を、固定版の bats で実行する入口。
# 検査の中身は持たない。検査は .bats にある。この入口は、引数の検査と、bats の起動と、終了コードの受け渡しだけを行う。
# 使い方: sh tests/lib/run-bats.sh <tests/bats/名前.bats> [unit|smoke|contract]
# 終了コードは bats のものをそのまま返す。INT と TERM は bats に伝えてから止まる。
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

# Why: bats を前面で待つと、この入口の trap は bats が終わるまで動かない。背景で起動して待つ。
if [ -n "$mode" ]; then
  "$bats_bin" --filter-tags "$mode" "$file" &
else
  "$bats_bin" "$file" &
fi
child=$!

# Why: 信号を受けたら、bats に同じ信号を送って終わるまで待つ。bats の teardown_file は TERM では動かないため、
# 子の後始末は、この trap と、各 .bats の中の後始末（helpers/common.bash）で行う。
trap 'kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' TERM
# Why: 背景の子は INT を無視して始まる（非対話シェル）。INT を受けたら TERM に読み替えて bats に送る。
trap 'kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 130' INT

rc=0
wait "$child" || rc=$?
exit "$rc"
