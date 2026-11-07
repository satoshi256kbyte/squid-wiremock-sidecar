#!/bin/sh
# M09 ローカル実行の入口。package.json の npm run <操作> から呼ばれる。
# 操作ごとに必要な前提だけを検査し、満たさなければ原因を示して止まる（FR-912）。
# 操作の中身は scripts/e2e-lib.sh にあり、ここは振り分けだけを行う。
# Why: 振り分けを薄くして、順序と終了コードの検査を関数単位で行えるようにするため。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"

usage() {
  cat >&2 <<'EOF'
使い方: sh scripts/e2e.sh <操作> [引数]
操作: start | test | logs | stop | clean | test:ci [シナリオ名...] | collect | check-production <ファイル> | contract
EOF
}

if [ $# -eq 0 ]; then
  usage
  exit 2
fi
op=$1
shift

# Why: 操作の終了コードを、set -e で途中終了させずに受けて、そのまま返すため。
rc=0
case $op in
  start)
    swsc_check_smoke_prereq || exit 1
    swsc_start_op || rc=$?
    exit "$rc"
    ;;
  test)
    swsc_check_smoke_prereq || exit 1
    swsc_test_op || rc=$?
    exit "$rc"
    ;;
  test:ci)
    swsc_check_smoke_prereq || exit 1
    if [ $# -gt 0 ]; then
      # Why: 名前を指定したときは、選んだ M08 のシナリオだけを実行する。終了コードは swsc_test_ci_scenarios が決める。
      swsc_test_ci_scenarios "$@" || rc=$?
      exit "$rc"
    fi
    # Why: 終了コードは swsc_test_ci_main が決めて exit する。ここでは上書きしない。
    swsc_test_ci_main
    ;;
  logs)
    swsc_check_stop_prereq || exit 1
    swsc_logs "$@"
    ;;
  stop)
    swsc_check_stop_prereq || exit 1
    swsc_stop
    ;;
  clean)
    swsc_check_stop_prereq || exit 1
    swsc_clean
    ;;
  collect)
    swsc_check_stop_prereq || exit 1
    swsc_collect
    ;;
  check-production)
    if [ $# -ne 1 ]; then
      printf 'FAIL: check-production は検査するファイルを1つ指定する\n' >&2
      exit 2
    fi
    swsc_need_cmd python3 || exit 1
    exec python3 -B "$ROOT/scripts/e2e-taskdef.py" check-production "$1"
    ;;
  contract)
    # 前提（認証情報を含む）は、MiniStack の起動と aws の呼び出しより前に検査する。
    swsc_check_contract_prereq || exit 1
    # shellcheck source=/dev/null
    . "$ROOT/scripts/e2e-contract.sh"
    contract_main
    ;;
  *)
    usage
    printf 'FAIL: 不明な操作: %s\n' "$op" >&2
    exit 2
    ;;
esac
