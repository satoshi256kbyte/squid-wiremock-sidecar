#!/bin/sh
# M07 の検査入口。
# unit の検査は tests/bats/m07-scenario-isolation.bats にある（Docker を使わない）。
# smoke は、まず unit（bats）を走らせ、続けて新基盤（taskdef）で WireMock と Squid を起動し、リセットと確認を実機で確かめる（T706）。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SELF="$ROOT/tests/m07-scenario-isolation.sh"
MODE=${1:-smoke}

case "$MODE" in
  unit | smoke) ;;
  *)
    printf 'usage: sh tests/m07-scenario-isolation.sh [unit|smoke]\n' >&2
    exit 2
    ;;
esac

cd "$ROOT"
BATS_FILE=$ROOT/tests/bats/m07-scenario-isolation.bats

if [ "$MODE" = unit ]; then
  exec sh "$ROOT/tests/lib/run-bats.sh" "$BATS_FILE" unit
fi

# smoke は unit に続けて走らせる。入れ子の子（M07_NESTED）は unit を走らせない（子が自分の unit をさらに走らせる再帰を防ぐ）。
if [ -z "${M07_NESTED:-}" ]; then
  sh "$ROOT/tests/lib/run-bats.sh" "$BATS_FILE" unit || exit 1
fi

# jq の実体は、固定版を照合して得る（マッピングの urlPath の取り出しに使う）。未導入や版違いは、ここで導入手順つきに止まる。
# shellcheck source=/dev/null
. "$ROOT/scripts/lib/resolve-tool.sh"
resolve_tool jq 's/^jq-//p' --version || exit 1
jq_bin=$RESOLVED_PATH
# 読み込みに副作用はない。関数を試験ごとに呼ぶために、ここで読み込む。
. "$ROOT/scripts/scenario-lib.sh"
# 新基盤の共通部品（ロック、起動、Client 実行、停止）。読み込みに副作用はない。
# Why: smoke が swsc_lock_enter、swsc_start_main などを使うため。
# shellcheck disable=SC2034 # 直後で読み込む scripts/e2e-lib.sh が SWSC_ROOT を参照する
SWSC_ROOT=$ROOT
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/scripts/e2e-runner.sh"

failures=0
total=0
# 一時ファイルは smoke が使う。削除だけを trap で行う。
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

record_fail() { # 検査名
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# 検査の本体を1つ走らせ、失敗したら記録する。関数の成否を終了コードで受ける。
check() { # 検査名 コマンド...
  _name=$1
  shift
  total=$((total + 1))
  if ! "$@"; then
    record_fail "$_name"
  fi
}

# 管理APIの mapping（JSON）から、name が一致する最初の mapping の urlPath を出す（smoke の名前の照合で使う）。
# 一致が無ければ空を出して成功する。一致したのに urlPath が無ければ失敗する。
mapping_urlpath_by_name() { # JSON のファイル、name
  # shellcheck disable=SC2016 # 単一引用符の中の $m と $n は jq の変数であり、シェルで展開させない。
  "$jq_bin" -r --arg n "$2" '
    ([.mappings[] | select(.name == $n)] | first) as $m
    | if $m == null then "" else ($m.request.urlPath // error("urlPath が無い")) end
  ' "$1"
}

smoke_wiremock_url=${WIREMOCK_URL:-http://127.0.0.1:8080}
smoke_client_url="http://api.example.com"
export WIREMOCK_URL="$smoke_wiremock_url"

smoke_dir="$tmp_root/smoke"
mkdir -p "$smoke_dir"

# Client を1回だけ実行する。標準出力と標準エラーは別々に残し、終了コードは client_rc へ入れる。
# Why: Squid の 3128 はホストへ公開しないため、proxy を通す要求は必ず Client から送る。
# 環境変数は NAME=VALUE の引数で渡す。Why: 値をシェルの文字列へ連結しないため。
smoke_client() { # NAME=VALUE...
  client_rc=0
  swsc_client_once_env "$SWSC_E2E_DIR/run" "$$" "$smoke_client_url" \
    "$smoke_dir/out" "$smoke_dir/err" "$@" || client_rc=$?
}

# Client を経路1つで実行し、最終の CLIENT_STATUS を返す。
smoke_client_status() { # 経路
  smoke_client TEST_API_PATH="$1"
  sed -n 's/^CLIENT_STATUS=//p' "$smoke_dir/out" | head -n 1
}

# WireMock の管理APIで、パス一致の呼び出し件数だけを読む。ジャーナルのリセットはしない。
wiremock_count() { # URLパス
  swsc_wiremock_count_path "$1"
}

# 対象のパスへ直接 HTTP ステータスを読む。WireMock の管理外の経路を、Squid を通さずに見る。
smoke_status() { # URLパス
  curl --connect-timeout 2 --max-time 10 --silent --output /dev/null --write-out '%{http_code}' "$smoke_wiremock_url$1" || true
}

smoke_reset_verify() {
  wiremock_reset && wiremock_verify_reset wiremock-scenarios/mappings
}

# 管理APIの name と request.urlPath が、scenario_path の結果と一致する（plan 6.2 の検査2）。
smoke_names_match() {
  curl --fail --silent --show-error --connect-timeout 2 --max-time 10 "$smoke_wiremock_url/__admin/mappings" \
    >"$smoke_dir/mappings.json" || return 1
  for _n in $(scenario_names); do
    _want=$(scenario_path "$_n") || return 1
    _got=$(mapping_urlpath_by_name "$smoke_dir/mappings.json" "$_n") || return 1
    [ "$_got" = "$_want" ] || return 1
  done
}

# 対照実験（検査3）。リセットなしで2回目は200、リセットを挟むと500に戻る。
smoke_control() {
  wiremock_reset || return 1
  _c1=$(smoke_status /api/error-500-then-200)
  _c2=$(smoke_status /api/error-500-then-200)
  wiremock_reset || return 1
  _c3=$(smoke_status /api/error-500-then-200)
  [ "$_c1" = 500 ] && [ "$_c2" = 200 ] && [ "$_c3" = 500 ]
}

# Test Client の通し実行（検査4、5）。リセットを挟んでから実行し、500 のあと 200 で総試行2回。
smoke_recovered_run() {
  wiremock_reset || return 1
  smoke_client TEST_API_PATH=/api/error-500-then-200
  [ "$client_rc" -eq 0 ] \
    && grep -qx 'CLIENT_STATUS=200' "$smoke_dir/out" \
    && grep -Fq 'CLIENT_DIAG result=success attempts=2 status=200' "$smoke_dir/err"
}

# 4シナリオの応答と、Squid 経由の到達（検査6）。Client から送る。
smoke_scenarios() {
  [ "$(smoke_client_status /api/users/123)" = 200 ] \
    && [ "$(smoke_client_status /api/ratelimit)" = 429 ] \
    && [ "$(smoke_client_status /api/slow-100)" = 200 ] \
    && [ "$(smoke_client_status /api/slow-5000)" = 200 ]
}

# ratelimit-429 の待機2秒と呼び出し回数（検査7）。呼び出し回数は診断の試行回数と一致する。
smoke_ratelimit() {
  _before=$(wiremock_count /api/ratelimit) || return 1
  smoke_client TEST_API_PATH=/api/ratelimit
  _after=$(wiremock_count /api/ratelimit) || return 1
  _attempts=$(sed -n 's/.*result=retries_exhausted attempts=\([0-9][0-9]*\) status=429.*/\1/p' "$smoke_dir/err")
  [ -n "$_attempts" ] \
    && grep -qx 'CLIENT_STATUS=429' "$smoke_dir/out" \
    && grep -Fq 'retry_after=2 wait=2 capped=0' "$smoke_dir/err" \
    && [ "$((_after - _before))" -eq "$_attempts" ]
}

# 手順3から7を1周する（検査9）。同じ起動の中で、リセットと再実行の結果が毎周同じになることを見る。
smoke_round() { # 周回の番号
  check "[周$1] 対照実験: リセットなしの2回目は200、リセット後は500" smoke_control
  check "[周$1] Test Client: 500 のあと 200 で総試行2回" smoke_recovered_run
  check "[周$1] リセットを挟んでも同じ結果（FR-706）" smoke_recovered_run
  check "[周$1] 4シナリオの応答と Squid 経由の到達" smoke_scenarios
  check "[周$1] ratelimit-429: 待機2秒と呼び出し回数" smoke_ratelimit
}

smoke_checks() {
  check "開始前のリセットと確認" smoke_reset_verify
  check "管理APIの name と urlPath が scenario_path と一致" smoke_names_match
  smoke_round 1
  smoke_round 2
}

# 起動、準備完了の待機、後始末。M06 の run_smoke と同じ方式。
# Why: ロックはトップレベルで1回だけ取る。失敗経路の子は SWSC_LOCK_HELD=1 を渡して取り直さない。
smoke_run() {
  swsc_lock_enter || exit 1
  cleanup() {
    rc=$?
    # Why: 失敗時だけ収集する。成功時は環境を残さず、終了コードは本体の結果のまま返す。
    if [ "$rc" -ne 0 ]; then swsc_collect || true; fi
    # 後始末でもリセットを試みる（FR-708）。失敗しても停止と解放は続ける。
    printf 'cleanup: reset attempted\n' >&2
    if wiremock_reset; then
      printf 'cleanup: reset ok\n' >&2
    else
      printf 'cleanup: reset failed (ignored)\n' >&2
    fi
    swsc_stop || true
    rm -rf "$tmp_root" || true
    swsc_lock_leave || { [ "$rc" -ne 0 ] || rc=1; }
    exit "$rc"
  }
  trap cleanup EXIT
  # 中断でも EXIT の後始末を通す。終了コードは cleanup が保つ。
  trap 'exit 130' INT
  trap 'exit 143' TERM

  swsc_start_main

  _i=0
  until curl --fail --silent --show-error --max-time 5 "$smoke_wiremock_url/__admin/mappings" >/dev/null 2>&1; do
    _i=$((_i + 1))
    [ "$_i" -lt 60 ] || { printf 'FAIL: WireMock の管理APIが準備できない\n' >&2; exit 1; }
    sleep 1
  done
  # Squid 経由の準備は Client で確かめる。Squid の待ち受けは swsc_start_main が確かめ、ホストからは送らない。
  _i=0
  until [ "$(smoke_client_status /api/users/123)" = 200 ]; do
    _i=$((_i + 1))
    [ "$_i" -lt 60 ] || { printf 'FAIL: Squid 経由の疎通が準備できない\n' >&2; exit 1; }
    sleep 1
  done

  smoke_checks

  # 後始末の確認: 停止のあと、管理対象（接頭辞とラベルの両方に一致）が残っていないこと。
  swsc_stop || exit 1
  check "終了後に管理対象の残存がない" swsc_check_managed_empty
  # 失敗経路は子の検査入口を起動するため、親のスタックを畳んでから行う。
  # 子の中では行わない（子が自分の失敗経路をさらに起動する再帰を防ぐ）。
  if [ -z "${M07_NESTED:-}" ]; then
    smoke_failure_path
  fi
}

# 失敗経路（検査8、plan.md 6.3）。本物の検査入口を子として起動し、後始末を確かめる。
# 本番のスクリプトに注入用の分岐は入れない。
smoke_clean_after() { # 子の一時ディレクトリ
  [ -z "$(ls -A "$1")" ] && swsc_check_managed_empty
}

# アサーション失敗の代わりに、WireMock の管理APIに届かない宛先を渡す。
# 準備完了の待ちが時間切れで終わり、終了コード1で止まる。後始末のリセットは失敗する。
# Why: 親がロックを持つので、子は SWSC_LOCK_HELD=1 で取り直さない。
smoke_case_assert() {
  _t=$(mktemp -d "$tmp_root/child.XXXXXX") || return 1
  _rc=0
  env WIREMOCK_URL=http://127.0.0.1:9 M07_NESTED=1 SWSC_LOCK_HELD=1 TMPDIR="$_t" sh "$SELF" smoke \
    >/dev/null 2>"$smoke_dir/child-assert.err" || _rc=$?
  [ "$_rc" -eq 1 ] \
    && grep -Fq 'cleanup: reset attempted' "$smoke_dir/child-assert.err" \
    && smoke_clean_after "$_t"
}

# 子を起動し、管理APIが応答してから信号を送り、終了コードを標準出力へ出す。
# 子の信号の既定の動作を Python の preexec_fn で戻す。バックグラウンドのシェルは INT を無視するため。
smoke_child_signal() { # 信号名 子の一時ディレクトリ
  python3 - "$SELF" "$1" "$smoke_wiremock_url" "$2" "$smoke_dir/child-$1.err" <<'PY'
import http.client
import os
import signal
import subprocess
import sys
import time
import urllib.request

self_path, sig_name, admin, tmp_parent, err_path = sys.argv[1:6]
sig = {"INT": signal.SIGINT, "TERM": signal.SIGTERM}[sig_name]
# Why: 親が持つロックを子が取り直さないよう、SWSC_LOCK_HELD=1 を渡す（test:ci と同じ規約）。
env = dict(os.environ, M07_NESTED="1", SWSC_LOCK_HELD="1", TMPDIR=tmp_parent)

def restore_default_signals():
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, signal.SIG_DFL)

def note(message):
    # 診断は標準エラーへ出す。標準出力は呼び出し側が終了コードとして読むため、混ぜない。
    sys.stderr.write(f"signal-case {sig_name}: {message}\n")

def stop_child(proc):
    # 準備できなかった子も、信号で止めて後始末を走らせる。
    # Why not proc.kill(): SIGKILL は子のトラップを走らせず、管理対象の資源が残るため。
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()

started = time.time()
with open(err_path, "w") as err:
    proc = subprocess.Popen(["sh", self_path, "smoke"], env=env,
                            stdout=subprocess.DEVNULL, stderr=err,
                            preexec_fn=restore_default_signals)
    ready = False
    last_error = "なし"
    deadline = started + 180
    while time.time() < deadline and proc.poll() is None:
        try:
            with urllib.request.urlopen(admin + "/__admin/mappings", timeout=2) as resp:
                if resp.status == 200:
                    ready = True
                    break
        # HTTPException は OSError ではない。ここで落とすと、待機の上限を待たずに原因不明で終わる。
        except (OSError, http.client.HTTPException) as exc:
            last_error = type(exc).__name__
            time.sleep(1)
    ready_after = time.time() - started
    if not ready:
        note(f"管理APIが準備できない（待機 {ready_after:.0f} 秒、子の終了コード={proc.poll()}、最後の例外={last_error}）")
        if proc.poll() is None:
            stop_child(proc)
        print("not-ready")
        sys.exit(0)
    proc.send_signal(sig)
    try:
        rc = proc.wait(timeout=120)
        note(f"準備まで {ready_after:.0f} 秒、信号から終了まで {time.time() - started - ready_after:.0f} 秒、終了コード={rc}")
        print(rc)
    except subprocess.TimeoutExpired:
        note(f"信号から120秒たっても終了しない（準備まで {ready_after:.0f} 秒）")
        proc.kill()
        proc.wait()
        print("timeout")
PY
}

# 信号の検査が外れたとき、原因を特定できるように、子の標準エラーの末尾と残存を出す。
# Why: 子の標準エラーと一時ディレクトリは、検査の後始末で消える。外れた時点で残さないと、事後に確かめられない。
smoke_signal_diag() { # 信号名 子の終了コード 期待する終了コード 子の一時ディレクトリ
  printf 'DIAG: %s: 子の終了コード=%s 期待=%s\n' "$1" "$2" "$3" >&2
# shellcheck disable=SC2012 # 引数の $4 は smoke_case_signal が mktemp -d で作った子の一時ディレクトリ。名前は診断表示にだけ使う
  printf 'DIAG: %s: 一時ディレクトリの残り=[%s] 管理対象の残存=%s件\n' "$1" \
    "$(ls -A "$4" 2>/dev/null | tr '\n' ' ')" "$(docker ps -a -q --filter "label=$SWSC_LABEL" 2>/dev/null | wc -l | tr -d ' ')" >&2
  printf 'DIAG: %s: 子の標準エラーの末尾 20 行\n' "$1" >&2
  grep -v 'Making directories' "$smoke_dir/child-$1.err" 2>/dev/null | tail -n 20 | sed 's/^/  | /' >&2 || true
}

smoke_case_signal() { # 信号名 期待する終了コード
  _t=$(mktemp -d "$tmp_root/child.XXXXXX") || return 1
  _rc=$(smoke_child_signal "$1" "$_t") || return 1
  if [ "$_rc" = "$2" ] \
    && grep -Fq 'cleanup: reset attempted' "$smoke_dir/child-$1.err" \
    && smoke_clean_after "$_t"; then
    return 0
  fi
  smoke_signal_diag "$1" "$_rc" "$2" "$_t"
  return 1
}

smoke_failure_path() {
  check "アサーション失敗: 終了コード1を保ち、リセットを試み、残存と一時ファイルがない" smoke_case_assert
  check "INT: 終了コード130、リセットを試み、残存と一時ファイルがない" smoke_case_signal INT 130
  check "TERM: 終了コード143、リセットを試み、残存と一時ファイルがない" smoke_case_signal TERM 143
}

smoke_run
if [ "$failures" -ne 0 ]; then
  printf 'M07 smoke: %s of %s checks failed\n' "$failures" "$total" >&2
  exit 1
fi
printf 'M07 scenario isolation smoke passed (%s checks)\n' "$total"
