#!/bin/sh
# M03 WireMock シナリオの入口。検査の中身は tests/bats/m03-wiremock-scenarios.bats にある。
#   unit:  Docker を使わない判定の検査（validate_json、validate_mapping）。
#   smoke: WireMock を起動し、その上で bats の smoke の検査を行い、最後に止める。起動と停止はこの入口が行う。
# 引数を省略すると smoke になる（品質ゲートの既存の呼び出しを変えないため）。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

MODE=${1:-smoke}
case "$MODE" in
  unit | smoke) ;;
  *)
    printf '%s\n' '使い方: sh tests/m03-wiremock-scenarios.sh [unit|smoke]' >&2
    exit 2
    ;;
esac
BATS_FILE=$ROOT/tests/bats/m03-wiremock-scenarios.bats

if [ "$MODE" = unit ]; then
  exec sh "$ROOT/tests/lib/run-bats.sh" "$BATS_FILE" unit
fi

# smoke: 新基盤の共通部品で WireMock を起動する。
# shellcheck disable=SC2034 # 読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する（出力先の既定値）
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"

wiremock_url="${WIREMOCK_URL:-http://127.0.0.1:8080}"

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

attempt=0
until curl --fail --silent --show-error "$wiremock_url/__admin/mappings" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  [ "$attempt" -lt 30 ] || exit 1
  sleep 1
done

# Why: bats は背景で起動して待つ。非対話シェルの背景の子は INT を無視して始まるため、INT は TERM に読み替えて子に送る。
# Why: 子が終わるまで待ってから後始末（cleanup）へ進む。終わる前に後始末を走らせると、テストが Docker の資源を作り続けるため。
sh "$ROOT/tests/lib/run-bats.sh" "$BATS_FILE" smoke &
bats_pid=$!
trap 'kill -TERM "$bats_pid" 2>/dev/null || true; wait "$bats_pid" 2>/dev/null || true; exit 143' TERM
trap 'kill -TERM "$bats_pid" 2>/dev/null || true; wait "$bats_pid" 2>/dev/null || true; exit 130' INT

rc=0
wait "$bats_pid" || rc=$?
if [ "$rc" -eq 0 ]; then
  printf '%s\n' 'M03 WireMock scenarios smoke test passed'
fi
exit "$rc"
