#!/bin/sh
# M02 Squid 経路の検査の入口。検査の中身は tests/bats/m02-routing-smoke.bats にある。
# 新基盤（ECSタスク定義方式、pause 共有 namespace）で起動し、bats の smoke の検査を走らせ、最後に止める。
# 起動と停止はこの入口が行う（ロック、trap、失敗時の収集）。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

BATS_FILE=$ROOT/tests/bats/m02-routing-smoke.bats

# shellcheck disable=SC2034 # 読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する（出力先の既定値）
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"

# Why: 固定ポートのロックは入口と同じ規約で1回だけ取る。取れなければ、他の実行の swsc- に触れずに止まる。
swsc_lock_enter || exit 1

# shellcheck disable=SC2329 # trap EXIT の文字列で呼ばれるため、直接の参照は無い。
cleanup() {
  rc=$?
  # Why: 失敗時だけ収集する。成功時は環境を残さず、終了コードは本体の結果のまま返す。
  if [ "$rc" -ne 0 ]; then swsc_collect || true; fi
  swsc_stop || true
  swsc_lock_leave || { [ "$rc" -ne 0 ] || rc=1; }
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

swsc_start_main

# Why: 起動の情報は、この入口の PID（$$）で登録されている。検査が Client を呼ぶときに同じ値を使えるように渡す。
SWSC_RUN_ID=$$
export SWSC_RUN_ID

# Why: bats は背景で起動して待つ。非対話シェルの背景の子は INT を無視して始まるため、INT は TERM に読み替えて子に送る。
# Why: 子が終わるまで待ってから後始末（cleanup）へ進む。終わる前に後始末を走らせると、テストが Docker の資源を作り続けるため。
sh "$ROOT/tests/lib/run-bats.sh" "$BATS_FILE" smoke &
bats_pid=$!
trap 'kill -TERM "$bats_pid" 2>/dev/null || true; wait "$bats_pid" 2>/dev/null || true; exit 143' TERM
trap 'kill -TERM "$bats_pid" 2>/dev/null || true; wait "$bats_pid" 2>/dev/null || true; exit 130' INT

rc=0
wait "$bats_pid" || rc=$?
if [ "$rc" -eq 0 ]; then
  printf '%s\n' 'M02 Squid routing smoke test passed'
fi
exit "$rc"
