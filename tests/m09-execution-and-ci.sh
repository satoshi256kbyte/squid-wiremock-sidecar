#!/bin/sh
# M09 ローカル実行とCIの検査入口。
# unit は Docker と AWS CLI を使わず、偽の docker、aws、docker-compose を PATH の先頭に置いて確かめる。
# smoke は Docker を使う実通信の検査（AWS CLI と認証情報は使わない）。contract は利用者の端末と CI だけで実行する。
set -eu

MODE=${1:-smoke}
if [ $# -gt 1 ]; then
  printf 'FAIL: 引数が多い（モードは1つだけ指定する）\n' >&2
  exit 2
fi
case $MODE in
  unit | smoke | contract) ;;
  *)
    printf 'FAIL: 不明なモード: %s（unit、smoke、contract のいずれか）\n' "$MODE" >&2
    exit 2
    ;;
esac

# Why: 読み込み（M09_LIB_ONLY=1、M09_LIB_ROOT）のときは、呼び出し側が渡したルートを使う。読み込み時の $0 は bats のものになるため。
# Why: M09_LIB_ONLY=1 は bats が入口を読むときだけ使う。環境変数に残ったまま起動すると、検査を飛ばして成功扱いになるため、bats の外では拒否する。
if [ "${M09_LIB_ONLY:-}" = 1 ] && [ -z "${BATS_TEST_FILENAME:-}" ]; then
  printf 'FAIL: M09_LIB_ONLY=1 は bats の読み込みだけで使う。検査は実行されない\n' >&2
  exit 2
fi
if [ "${M09_LIB_ONLY:-}" = 1 ] && [ -n "${M09_LIB_ROOT:-}" ]; then
  ROOT=$M09_LIB_ROOT
else
  ROOT=$(cd "$(dirname "$0")/.." && pwd)
fi

# SIGINT が無視されたまま起動された場合は、INT の検査が原因の分かりにくい形で落ちるため、先に止める。
# Why: 背景（&）や nohup で起動すると、シェルは SIGINT を無視して始まり、シェルの中から trap で受けられない（POSIX）。
# Why not: 検査の中で無視を解除する方式は採らない。無視された状態を戻せるシェルは無いため。
if [ "${M09_LIB_ONLY:-}" != 1 ] && [ "$MODE" != contract ]; then
  _int_rc=0
  sh -c 'kill -INT $$; exit 0' >/dev/null 2>&1 || _int_rc=$?
  if [ "$_int_rc" -eq 0 ]; then
    printf 'FAIL: SIGINT が無視された状態で起動された（背景起動や nohup など）。前面のシェルで実行する\n' >&2
    exit 2
  fi
fi

# 偽の docker、aws、docker-compose の呼び出しを、それぞれ別の記録に残す。
# Why: 呼び出しの有無で、入口が Docker や AWS CLI に触れていないことを確かめるため。
TMP=
total=0
failures=0

# 失敗を確実に止める。Why: 検査の関数は if の条件として呼ばれ、set -e が効かないため。
must() {
  "$@" || {
    printf '    確認に失敗: %s\n' "$*" >&2
    exit 1
  }
}

# 終了コードだけを比べる。標準出力と標準エラーは捨てる。
rc_is() { # 期待の終了コード コマンド...
  _want=$1
  shift
  _rc=0
  "$@" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq "$_want" ]
}

# 検査を1件ずつ、サブシェルで走らせて結果を記録する。
check() { # 名前 関数
  _name=$1
  shift
  total=$((total + 1))
  # Why: 検査どうしで作業ファイルを共有すると、前の検査の出力が後の「無いこと」の検査を壊すため、
  # 検査ごとに作業場所を空にする（偽の呼び出し記録も含む）。
  find "$TMP" -mindepth 1 -maxdepth 1 ! -name case.log -exec rm -rf {} +
  # Why: ロックの取り残しが次の検査に混ざると、順序の検査が原因の分からない形で落ちるため、検査ごとに消す。
  if [ -n "${UNIT_LOCK_BASE:-}" ]; then find "$UNIT_LOCK_BASE" -mindepth 1 -delete; fi
  if ("$@") >"$TMP/case.log" 2>&1; then
    printf 'ok: %s\n' "$_name"
  else
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$_name"
    sed 's/^/    /' "$TMP/case.log" >&2
  fi
}

# 偽の docker、aws などの用意（make_base_bin など4つ）は、tests/bats/helpers/fakes.bash の1か所にある（T-R0278）。
# shellcheck source=/dev/null
. "$ROOT/tests/bats/helpers/fakes.bash"

# 入口を、環境変数を外した状態で起動する。Why: 利用者の AWS 設定が検査に混ざるのを防ぐため。
run_e2e() { # PATH 操作...
  _p=$1
  shift
  env -i PATH="$_p" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_JQ="$SWSC_JQ" sh "$ROOT/scripts/e2e.sh" "$@"
}

# ---------------------------------------------------------------------------
# T907: 入口の骨格と前提検査
# ---------------------------------------------------------------------------

# S26 T2616: test:ci のシナリオ名は、ロックと docker の前に検査する。不明な名前は終了コード2。
# S26 T2616: test:ci の名前指定。子の終了コードを返し、ロックを解放する。
# S26 T2616: 親だけが TERM を受けても、子へ TERM を送り、子の後始末を待ってからロックを解放する。

# docker-compose の呼び出しを、コマンドの位置で探す（コメントは対象外）。
fr920_hits() { # ファイル...
  grep -hE '(^|[;&|(:-])[[:space:]]*docker[- ]compose([[:space:]]|$)' "$@" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# T908: テンプレートと生成
# ---------------------------------------------------------------------------

# テンプレートから完成版を作る（ローカルの値）。引数: 出力先 [テンプレート]
render_local() { # 出力先 [テンプレート]
  _tpl=${2:-$ROOT/ecs/task-definition.template.json}
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render --template "$_tpl" --out "$1" \
    --client-image swsc-client:e2e --squid-image swsc-squid:e2e \
    --profile local --upstream mock --mock-host swsc-wiremock --mock-port 8080
}

# JSON を書き換える。引数: 入力 出力 Python の文（d が辞書）
mutate() { # 入力 出力 コード
  python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
exec(sys.argv[3])
open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
' "$1" "$2" "$3"
}

# ---------------------------------------------------------------------------
# T909: 本番向けの検査
# ---------------------------------------------------------------------------

render_production() { # 出力先 上流
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render --template "$ROOT/ecs/task-definition.template.json" \
    --out "$1" --client-image swsc-client:prod --squid-image swsc-squid:prod \
    --profile production --upstream "$2"
}

check_production() { # ファイル
  python3 -B "$ROOT/scripts/e2e-taskdef.py" check-production "$1"
}

# ---------------------------------------------------------------------------
# T910: Squid のイメージ
# ---------------------------------------------------------------------------

# 派生を1回走らせる。引数: 上流 出力先 [元ファイル] [ホスト] [ポート]。環境変数は外して渡す。
derive() {
  _src=${3:-$ROOT/squid-config/squid.conf}
  env -i PATH=/usr/bin:/bin SQUID_UPSTREAM="$1" SQUID_MOCK_HOST="${4-swsc-wiremock}" \
    SQUID_MOCK_PORT="${5-8080}" sh "$ROOT/ecs/squid/derive-config.sh" "$_src" "$2"
}

# 受理側の境界。Why: 5桁（10000〜65535）を弾くバグ（?????* は5文字以上）を、拒否側の値だけでは見逃したため。
# 元のエントリポイントと squid を偽物に差し替えた写しを作る（本物のパスだけを書き換える）。
entry_sandbox() { # 置き場
  mkdir -p "$1/bin"
  cp "$ROOT/ecs/squid/derive-config.sh" "$1/derive.sh"
  cp "$ROOT/squid-config/squid.conf" "$1/src.conf"
  printf '#!/bin/sh\necho "squid $*" >>"%s/calls"\nexit 0\n' "$1" >"$1/bin/squid"
  printf '#!/bin/sh\necho "entry $*" >>"%s/calls"\nexit 0\n' "$1" >"$1/fakeentry.sh"
  sed -e "s#/usr/local/bin/swsc-derive-config.sh#$1/derive.sh#g" \
    -e "s#/etc/squid/squid.conf.src#$1/src.conf#g" \
    -e "s#/etc/squid/squid.conf#$1/out.conf#g" \
    -e "s#/usr/local/bin/entrypoint.sh#$1/fakeentry.sh#g" \
    "$ROOT/ecs/squid/entrypoint.sh" >"$1/entry.sh"
  chmod +x "$1/bin/squid" "$1/fakeentry.sh" "$1/derive.sh" "$1/entry.sh"
}

# 構文の検査（plan 5.1）。Python の検査は、キャッシュを一時置き場へ逃がし、リポジトリに __pycache__ を残さない。
# ---------------------------------------------------------------------------
# T911: MiniStackの契約検証（contract）
# ---------------------------------------------------------------------------

# 偽の docker と aws を置く。挙動は置き場のフラグファイルで切り替え、記録は $TMP と SWSC_TEST_SEQ へ書く。
# Why: 偽の中に値を埋め込まず、検査ごとに変えるのはファイルだけにするため（T912 と同じ方法）。
contract_fakes() { # 置き場
  mkdir -p "$1"
  cat >"$1/docker" <<'FAKE'
#!/bin/sh
echo "docker $*" >>"$SWSC_TEST_SEQ"
echo "docker $*" >>"$SWSC_TEST_DIR/rec-docker"
case "$1" in
  run)
    if [ -f "$SWSC_TEST_DIR/docker-run-fail" ]; then exit 1; fi
    echo fakeid ;;
  # ラベルで絞った一覧。利用者の同名コンテナ（ラベル無し）が相手のときは何も返さない。
  ps) if [ ! -f "$SWSC_TEST_DIR/foreign-ministack" ]; then echo fakeid; fi ;;
  inspect) cat "$SWSC_TEST_DIR/inspect-out" 2>/dev/null ;;
esac
exit 0
FAKE
  cat >"$1/aws" <<'FAKE'
#!/bin/sh
echo "aws $*" >>"$SWSC_TEST_SEQ"
echo "aws $*" >>"$SWSC_TEST_DIR/rec-aws"
env | sed -n 's/^\(AWS_[A-Z0-9_]*\)=.*/\1/p' >>"$SWSC_TEST_DIR/rec-aws-env"
case "$*" in
  *list-task-definitions*)
    if [ -f "$SWSC_TEST_DIR/aws-list-fail" ]; then exit 1; fi
    # Why: 終了の経路（INT、TERM）を確かめるため、呼び出し元のシェルへ信号を送る。
    if [ -f "$SWSC_TEST_DIR/aws-int" ]; then kill -INT "$PPID"; fi
    if [ -f "$SWSC_TEST_DIR/aws-term" ]; then kill -TERM "$PPID"; fi ;;
  *register-task-definition*)
    if [ -f "$SWSC_TEST_DIR/aws-register-fail" ]; then exit 1; fi
    echo 1 ;;
  *describe-task-definition*) cat "$SWSC_TEST_DIR/describe.json" ;;
esac
exit 0
FAKE
  chmod +x "$1/docker" "$1/aws"
}

# 完成版（本物の変換で作る）と、describe の形の写しを作る。
# 写しは環境変数の順序を変え、AWS が足す空の既定項目を入れる（G2の観測3の形に寄せる）。
contract_base() {
  render_local "$TMP/taskdef.json" || return 1
  python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
out = {"networkMode": d["networkMode"], "containerDefinitions": []}
for c in reversed(d["containerDefinitions"]):
    out["containerDefinitions"].append({
        "name": c["name"], "image": c["image"], "essential": c["essential"],
        "environment": list(reversed(c.get("environment", []))),
        "portMappings": [dict(p, hostPort=p["containerPort"]) for p in c.get("portMappings", [])] or None,
        "dependsOn": c.get("dependsOn") or None,
        "healthCheck": c.get("healthCheck") or None,
        "mountPoints": [], "volumesFrom": [],
    })
json.dump(out, open(sys.argv[2], "w", encoding="utf-8"))
' "$TMP/taskdef.json" "$TMP/describe.json"
}

# 偽の Docker と AWS を入れた置き場を作り、完成版と写しを用意する。
contract_setup() {
  contract_fakes "$TMP/cfake"
  make_base_bin "$TMP/cbase"
  contract_base
}

# 契約検証の本体を、偽のPATHと偽のダミー認証情報で評価する。
# Why: 実際の docker と aws に触れず、利用者の AWS 設定を混ぜないため。出力先も一時領域へ向ける。
contract_run() { # 本体
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、子の sh が環境変数から展開する。親のシェルでは展開させない意図。 子の sh が SWSC_ROOT から e2e-lib.sh と e2e-contract.sh を読み、eval で与えた文を評価する。
  # shellcheck disable=SC2031 # SWSC_JQ は run_unit で一度だけ設定し、以後は変えない。子の sh に渡すだけの読み取り。
  env -i PATH="$TMP/cfake:$TMP/cbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_E2E_DIR="$TMP/e2e" SWSC_JQ="$SWSC_JQ" \
    SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_LOG_DIR="$TMP/logs" \
    SWSC_TEST_DIR="$TMP" SWSC_TEST_SEQ="$TMP/seq.log" SWSC_CONTRACT_WAIT_SECONDS=1 \
    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; . "$SWSC_ROOT/scripts/e2e-contract.sh"; eval "$1"' sh "$1"
}

# 本体を実行し、終了コードを RC に、標準出力と標準エラーを out と err に残す。
contract_go() { # 本体
  RC=0
  # shellcheck disable=SC2034 # RC は、移した bats の検査が読む（tests/bats/m09-execution-and-ci.bats）
  contract_run "$1" >"$TMP/out" 2>"$TMP/err" || RC=$?
}

# 文字列 $1 が、テキスト $2 の中に一行として含まれるか。
has_text() { # テキスト 文字列
  printf '%s\n' "$1" | grep -q -F -- "$2"
}

# 記録の中で、先の文字列が後の文字列より前の行にある（どちらも記録にある）。
seq_before() { # 先の文字列 後の文字列
  _a=$(seq_line "$1")
  _b=$(seq_line "$2")
  [ -n "$_a" ] && [ -n "$_b" ] && [ "$_a" -lt "$_b" ]
}

# 記録の最後の行に、文字列があるか。Why: 後始末（docker rm）が最後に来ることを確かめるため。
seq_last_is() { # 文字列
  tail -n 1 "$TMP/seq.log" 2>/dev/null | grep -q -F -- "$1"
}

# describe の写しの一部を書き換える。C はコンテナ名で引ける定義、d は全体。
desc_mutate() { # Python の文
  python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
C = {c["name"]: c for c in d["containerDefinitions"]}
exec(sys.argv[3])
open(sys.argv[2], "w", encoding="utf-8").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
' "$TMP/describe.json" "$TMP/describe-bad.json" "$1"
}

compare_cli() { # 完成版 describe
  python3 -B "$ROOT/scripts/e2e-taskdef.py" compare "$1" "$2"
}

# 完成版と写しが一致することを前提に、写しを1か所だけ変えて compare が不一致（1）になるかを確かめる。
# 第2引数は、標準出力と標準エラーに出てはいけない文字列（値を出さないことの確認）。
compare_mismatch() { # Python の文 [出てはいけない文字列]
  contract_base || return 1
  desc_mutate "$1" || return 1
  _rc=0
  compare_cli "$TMP/taskdef.json" "$TMP/describe-bad.json" >"$TMP/out" 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  if [ -n "${2:-}" ]; then
    must [ -z "$(grep -F -- "$2" "$TMP/out" || true)" ]
  fi
}

# shellcheck disable=SC2016 # 関数定義の文字列。$SWSC_TEST_SEQ は、contract_go の子の sh で関数を実行するときに展開する。親では展開させない意図。
# shellcheck disable=SC2034 # この変数は、移した bats の検査（tests/bats/m09-execution-and-ci.bats）が使う
CONTRACT_FREE='swsc_port_in_use() { echo "port" >>"$SWSC_TEST_SEQ"; return 1; }'
# shellcheck disable=SC2016 # 関数定義の文字列。$SWSC_TEST_SEQ は、contract_go の子の sh で関数を実行するときに展開する。親では展開させない意図。
# shellcheck disable=SC2034 # COLLECT_DEF は、移した bats の検査（tests/bats/m09-execution-and-ci.bats）が使う
COLLECT_DEF='swsc_collect() { echo "collect" >>"$SWSC_TEST_SEQ"; }'

# 実機（MiniStack 1.5.37）の inspect の形。EXPOSE しただけのポートは null で載る（contract の C4 の実測）。

# ---------------------------------------------------------------------------
# T912: pause方式のランナー
# ---------------------------------------------------------------------------

# 偽の docker、docker-compose、curl を置く。記録先は環境変数で渡し、偽の中に値を埋め込まない。
# Why: 起動順は docker と curl の呼び出しの前後で確かめるため、1本の記録（SWSC_TEST_SEQ）に両方を書く。
runner_fakes() { # 置き場
  mkdir -p "$1"
  cat >"$1/docker" <<'FAKE'
#!/bin/sh
echo "docker $*" >>"$SWSC_TEST_SEQ"
echo "docker $*" >>"$SWSC_TEST_DIR/rec-docker"
case "$1" in
  inspect)
    case "$*" in
      *State.Running*) if [ -f "$SWSC_TEST_DIR/running-out" ]; then cat "$SWSC_TEST_DIR/running-out"; else echo true; fi ;;
      *State.Health*) if [ -f "$SWSC_TEST_DIR/health-out" ]; then cat "$SWSC_TEST_DIR/health-out"; else echo healthy; fi ;;
      *) echo healthy ;;
    esac ;;
  ps)
    case "$*" in
      *label=swsc.managed=true*) cat "$SWSC_TEST_DIR/ps-out" 2>/dev/null ;;
      *) cat "$SWSC_TEST_DIR/ps-all" 2>/dev/null ;;
    esac ;;
  network)
    if [ "$2" = ls ]; then cat "$SWSC_TEST_DIR/net-out" 2>/dev/null; fi ;;
  run)
    case "$*" in
      *swsc-probe-*)
        if [ -f "$SWSC_TEST_DIR/probe-fail" ]; then exit 1; fi ;;
      *swsc-client-*)
        if [ -f "$SWSC_TEST_DIR/client-rc" ]; then exit "$(cat "$SWSC_TEST_DIR/client-rc")"; fi ;;
      *" -d "*) echo fakeid ;;
    esac ;;
esac
exit 0
FAKE
  cat >"$1/curl" <<'FAKE'
#!/bin/sh
echo "curl $*" >>"$SWSC_TEST_SEQ"
echo "curl $*" >>"$SWSC_TEST_DIR/rec-curl"
if [ -f "$SWSC_TEST_DIR/curl-down" ]; then exit 7; fi
if [ -f "$SWSC_TEST_DIR/curl-body" ]; then cat "$SWSC_TEST_DIR/curl-body"; fi
exit 0
FAKE
  cat >"$1/docker-compose" <<'FAKE'
#!/bin/sh
echo "docker-compose $*" >>"$SWSC_TEST_SEQ"
exit 0
FAKE
  chmod +x "$1/docker" "$1/curl" "$1/docker-compose"
}

# 偽のPATHと、本物の変換で作った完成版を用意する。
runner_setup() {
  runner_fakes "$TMP/rfake"
  make_base_bin "$TMP/rbase"
  mkdir -p "$TMP/run"
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render \
    --template "$ROOT/ecs/task-definition.template.json" --out "$TMP/taskdef.json" \
    --client-image swsc-client:e2e --squid-image swsc-squid:e2e --profile local \
    --upstream mock --mock-host swsc-wiremock --mock-port 8080
}

# 偽のPATHで、ランナーを読み込んだ子シェルに本体を評価させる。
# Why: 実際の docker と curl に触れず、利用者の AWS 設定や環境変数を検査に混ぜないため。
runner_run() { # 本体
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、子の sh が環境変数から展開する。親のシェルでは展開させない意図。 子の sh が SWSC_ROOT から e2e-lib.sh と e2e-runner.sh を読み、eval で与えた文を評価する。
  # shellcheck disable=SC2031 # SWSC_JQ は run_unit で一度だけ設定し、以後は変えない。子の sh に渡すだけの読み取り。
  env -i PATH="$TMP/rfake:$TMP/rbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_TEST_DIR="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_JQ="$SWSC_JQ" \
    SWSC_TEST_SEQ="$TMP/seq.log" SWSC_WAIT_SECONDS=2 \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; . "$SWSC_ROOT/scripts/e2e-runner.sh"; eval "$1"' sh "$1"
}

# 記録の中で、固定の文字列を含む最初の行番号を返す。無ければ空。
seq_line() { # 文字列
  grep -n -F -- "$1" "$TMP/seq.log" 2>/dev/null | head -1 | cut -d: -f1 || true
}

# 完成版の一部を書き換えた写しを作る（d は完成版の辞書）。
runner_mutate() { # Python の文
  python3 -B -c "import json, sys
d = json.load(open(sys.argv[1]))
$1
json.dump(d, open(sys.argv[2], 'w'))" "$TMP/taskdef.json" "$TMP/bad.json"
}

runner_docker_args() { # 完成版 出力先
  python3 -B "$ROOT/scripts/e2e-taskdef.py" docker-args --taskdef "$1" --out-dir "$2" \
    --pause-name swsc-pause --run-id 4242
}

# image は docker run のオプションとして読まれない。Why: 先頭が - の image は --privileged などを通してしまう（レビュー M-2）。
# 待機は、コンテナが止まっていれば上限を待たずに止まる。止まっていなければ、従来どおり上限で止まる。
# ---------------------------------------------------------------------------
# T913: 入口の完成（start、test、stop、clean、test:ci、collect、trap）
# ---------------------------------------------------------------------------

# 入口の検査用の偽の docker、docker-compose、aws、curl を置く。
# 挙動は置き場のフラグファイルで切り替え、記録は $SWSC_TEST_SEQ と $SWSC_TEST_DIR/rec-* へ書く。
# Why: 偽の中に値を埋め込まず、検査ごとに変えるのはファイルだけにする（T911、T912 と同じ方法）。
entry_fakes() { # 置き場
  mkdir -p "$1"
  cat >"$1/docker" <<'FAKE'
#!/bin/sh
echo "docker $*" >>"$SWSC_TEST_SEQ"
echo "docker $*" >>"$SWSC_TEST_DIR/rec-docker"
if [ -f "$SWSC_TEST_DIR/docker-fail" ]; then exit 1; fi
case "$1" in
  ps) cat "$SWSC_TEST_DIR/ps-out" 2>/dev/null ;;
  network) if [ "$2" = ls ]; then cat "$SWSC_TEST_DIR/net-out" 2>/dev/null; fi ;;
  inspect)
    if [ -f "$SWSC_TEST_DIR/no-containers" ]; then exit 1; fi
    case "$*" in
      *State.Running*) cat "$SWSC_TEST_DIR/running-out" 2>/dev/null || echo true ;;
      *State.Health*) echo healthy ;;
      *Config.Image*) echo 'name=/swsc-x image=ubuntu/squid:latest id=sha256:fake' ;;
      *) echo sha256:fake ;;
    esac ;;
  logs)
    if [ -f "$SWSC_TEST_DIR/no-containers" ] || [ -f "$SWSC_TEST_DIR/logs-fail" ]; then exit 1; fi
    cat "$SWSC_TEST_DIR/logs-out" 2>/dev/null || echo "log $*" ;;
  exec)
    if [ -f "$SWSC_TEST_DIR/no-containers" ] || [ -f "$SWSC_TEST_DIR/exec-fail" ]; then exit 1; fi
    echo "content $*" ;;
  version) echo 27.0 ;;
  build) if [ -f "$SWSC_TEST_DIR/build-fail" ]; then exit 1; fi; echo sha256:fake ;;
  run)
    case "$*" in
      *swsc-client-*)
        cat "$SWSC_TEST_DIR/client-out" 2>/dev/null
        exit "$(cat "$SWSC_TEST_DIR/client-rc" 2>/dev/null || echo 0)" ;;
      *" -d "*) echo fakeid ;;
    esac ;;
esac
exit 0
FAKE
  cat >"$1/docker-compose" <<'FAKE'
#!/bin/sh
echo "docker-compose $*" >>"$SWSC_TEST_SEQ"
exit 0
FAKE
  cat >"$1/aws" <<'FAKE'
#!/bin/sh
echo "aws $*" >>"$SWSC_TEST_SEQ"
echo "aws $*" >>"$SWSC_TEST_DIR/rec-aws"
exit 0
FAKE
  cat >"$1/curl" <<'FAKE'
#!/bin/sh
echo "curl $*" >>"$SWSC_TEST_SEQ"
echo "curl $*" >>"$SWSC_TEST_DIR/rec-curl"
if [ -f "$SWSC_TEST_DIR/curl-down" ]; then exit 7; fi
case "$*" in
  *"-X DELETE"*"/__admin/requests") exit 0 ;;
  *requests/reset*) echo "curl: (22) The requested URL returned error: 404" >&2; exit 22 ;;
  *) cat "$SWSC_TEST_DIR/curl-body" 2>/dev/null || echo '{"requests":[]}' ;;
esac
exit 0
FAKE
  chmod +x "$1/docker" "$1/docker-compose" "$1/aws" "$1/curl"
}

# 入口の環境（偽の PATH、利用者の AWS 設定と認証情報を外す）を作る。
entry_setup() {
  entry_fakes "$TMP/efake"
  make_base_bin "$TMP/ebase"
}

# scripts/e2e.sh を、偽の PATH と空の環境で実行する。出力先は一時領域へ向ける。
entry_run() { # 操作...
  # shellcheck disable=SC2031 # SWSC_JQ は run_unit で一度だけ設定し、以後は変えない。子の sh に渡すだけの読み取り。
  env -i PATH="$TMP/efake:$TMP/ebase" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_E2E_DIR="$TMP/e2e" SWSC_LOG_DIR="$TMP/logs" \
    SWSC_TEST_DIR="$TMP" SWSC_TEST_SEQ="$TMP/seq.log" SWSC_WAIT_SECONDS=2 SWSC_CONTRACT_WAIT_SECONDS=1 SWSC_JQ="$SWSC_JQ" \
    sh "$ROOT/scripts/e2e.sh" "$@"
}

# e2e-lib.sh と e2e-runner.sh を読み込んだ子シェルで、与えた文を評価する。関数の差し替えに使う。
lib_call() { # 文
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、子の sh が環境変数から展開する。親のシェルでは展開させない意図。 子の sh が SWSC_ROOT から e2e-lib.sh と e2e-runner.sh を読み、eval で与えた文を評価する。
  # shellcheck disable=SC2031 # SWSC_JQ は run_unit で一度だけ設定し、以後は変えない。子の sh に渡すだけの読み取り。
  env -i PATH="$TMP/efake:$TMP/ebase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_E2E_DIR="$TMP/e2e" \
    SWSC_LOG_DIR="$TMP/logs" SWSC_TEST_DIR="$TMP" SWSC_TEST_SEQ="$TMP/seq.log" SWSC_WAIT_SECONDS=2 SWSC_JQ="$SWSC_JQ" \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; . "$SWSC_ROOT/scripts/e2e-runner.sh"; eval "$1"' sh "$1"
}

# 偽の順序の記録（start、test、collect、stop）。戻り値は置き場のファイルで切り替える。
# shellcheck disable=SC2016 # 偽の関数定義の文字列。$SWSC_TEST_SEQ などは、lib_call の子の sh で関数を実行するときに展開する。親では展開させない意図。
# shellcheck disable=SC2034 # この変数は、移した bats の検査（tests/bats/m09-execution-and-ci.bats）が使う
CI_FAKES='swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; return "$(cat "$SWSC_TEST_DIR/rc-start" 2>/dev/null || echo 0)"; }
swsc_test_run() { echo test >>"$SWSC_TEST_SEQ"; return "$(cat "$SWSC_TEST_DIR/rc-test" 2>/dev/null || echo 0)"; }
swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; return "$(cat "$SWSC_TEST_DIR/rc-collect" 2>/dev/null || echo 0)"; }
swsc_stop() { echo stop >>"$SWSC_TEST_SEQ"; return 0; }'

# 記録の行を、順に並べた内容で比べる。
seq_is() { # 期待の行（改行区切り）
  [ "$(cat "$TMP/seq.log" 2>/dev/null)" = "$1" ]
}

# 認証情報を一切渡さずに、操作を前提検査の段階で止める（偽の docker が失敗する）。
# start、test、stop、clean、collect、logs、test:ci は、認証情報が無くても aws を呼ばない。
# 旧基盤のdocker-composeは、どの操作でも呼ばれない（偽の docker-compose が記録する）。
# ポートの確認は、自分の swsc- を止めた後に行い、使用中なら何も作らずに止まる。
# start_main は trap を持たない（test:ci の中で collect より先に stop が走るのを防ぐため）。
# 出力先を利用者のディレクトリへ上書きしても、目印が無ければ消さない（security-review の Low）。
# collect は識別情報を含むファイルを削除する。目印の無い既存ディレクトリでは、何も触れずに失敗する。
# test:ci の順序: start、test、collect、stop。失敗しても collect が stop より前に届く。
# collect の最中に TERM を受けても、EXIT の trap が collect と stop をやり直す（_done は stop の後に立てる）。
# start 操作（単独）: 失敗時は stop だけを呼び、collect は呼ばない。成功時は環境を残す。
# test 操作: INT と TERM のときだけ stop を呼ぶ。通常の失敗では環境を残す。
# test は Squid が稼働していなければ、Client を起動せずに止まる。
# collect: 対象が無くても0。missing.txt に名前を残す。
# 同じ収集を2回すると、同じ構造になる。元が消えた回は、既存の収集物を消さない。
# 識別情報は、コピーの上でマスクする。ARNと前後が数字でない12桁を消す。
# UUID の末尾が偶然12桁の数字でも、前が - なので識別情報として扱わない。
# マスクしても残るファイルは削除し、名前を scrub.txt に記録する。その回は終了コード1。
# 2回目は、元から取り直して識別情報が無いので0（scrub.txt は作り直される）。
# 一時物の検査: test の出力は一度ファイルへ書き、終了コードを取ってから表示する。
# 検査の項目1件: 状態（ステータスと受信数）が期待どおりなら PASS、違えば FAIL になる。
# Clientへ渡すベースURLが、引数の組み立ての影響を受けず、そのまま docker run に届く。
# Why: set -- が位置パラメータを入れ替えるため、$3 を後から参照すると --label が URL になった（実機で確認）。
# WireMock の受信記録は、DELETE /__admin/requests で消す。POST /__admin/requests/reset は 404 になる（実機で確認）。
# ---------------------------------------------------------------------------
# T914: smoke と contract のモード（実通信の検査）の配線と前提。
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# smoke の項目が、表（plan 5.2）の1から11の順に登録されている。
# contract の項目が、表（plan 5.4）のC1からC6の順に登録されている。
# smoke は unit を、Docker を呼ぶ前に実行する。Why: unit が落ちたらDockerを起動しないため（tasks T914）。
# 認証情報が無い（または test 以外、AWS_PROFILE あり）の contract は、unit も Docker も AWS CLI も呼ばずに止まる。
# Why: 認証情報の検査を最初に行うことで、既定の認証情報へ切り替わる経路を作らないため（FR-905）。
# ---------------------------------------------------------------------------
# T914: 実通信の検査（smoke）と契約の検査（contract）。
# 項目は表（plan 5.2、5.4）の順に smoke_item、contract_item で登録する。
# Why: 登録の1行に番号と関数を並べ、順序と抜けを unit で確かめられるようにするため。
# ---------------------------------------------------------------------------

SMOKE_HOLDER=m09-smoke-port-holder
# 識別情報の検出。scripts/e2e-lib.sh の SWSC_ID_RE と同じ。Why not 読み込み: 検査が lib の関数を使わずに済むため。
SMOKE_ID_RE='arn:aws|(^|[^0-9A-Za-z-])[0-9]{12}([^0-9A-Za-z-]|$)'

smoke_item() { # 番号 名前 関数
  check "$1 $2" "$3"
}

contract_item() { # 番号 名前 関数
  check "$1 $2" "$3"
}

# scripts/e2e.sh を、この検査の環境のまま呼ぶ。Why: smoke は AWS の環境変数を設定せず、呼び出しに AWS CLI を含めないため。
smoke_e2e() {
  sh "$ROOT/scripts/e2e.sh" "$@"
}

# 8080 が応答するか。Why: ポートの占有者を名前では判定できない（scripts/e2e-lib.sh と同じ理由）。
smoke_port_busy() { # ポート番号
  python3 -B -c '
import socket, sys
s = socket.socket()
s.settimeout(1)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    sys.exit(1)
finally:
    s.close()
sys.exit(0)
' "$1"
}

# swsc- の残り（コンテナ、ラベル付きのコンテナのID、ネットワーク）を出す。何も無ければ空。
smoke_swsc_left() {
  docker ps -a --format '{{.Names}}' | grep '^swsc-' || true
  docker ps -aq --filter label=swsc.managed=true
  docker network ls --format '{{.Name}}' | grep '^swsc-' || true
}

# 使い捨ての名前のコンテナが止まるまで待つ。止まれば終了コード、上限まで止まらなければ running を返して失敗する。
smoke_probe_exit() { # 名前 上限秒
  _lim=$(($(date +%s) + $2))
  while [ "$(docker inspect --format '{{.State.Running}}' "$1" 2>/dev/null || true)" = true ]; do
    if [ "$(date +%s)" -ge "$_lim" ]; then
      echo running
      return 1
    fi
    sleep 1
  done
  docker inspect --format '{{.State.ExitCode}}' "$1"
}

# 8080 を、swsc- の接頭辞を付けない名前の使い捨てのコンテナで塞ぐ。
# Why: 占有者の名前が swsc- でないことで、start が「swsc- 以外が使用中」として止まるかを確かめるため（項目6、7）。
smoke_holder_up() {
  docker rm -f "$SMOKE_HOLDER" >/dev/null 2>&1 || true
  # Why: alpine:3.20 の busybox に httpd は無い（G5、G2 の実験で not found）。待受けは nc の繰り返しで作る。
  docker run -d --name "$SMOKE_HOLDER" -p 127.0.0.1:8080:80 alpine:3.20 \
    sh -c 'while true; do printf "HTTP/1.0 200 OK\r\n\r\n" | nc -l -p 80; done' >/dev/null || return 1
  _lim=$(($(date +%s) + 30))
  until smoke_port_busy 8080; do
    [ "$(date +%s)" -lt "$_lim" ] || return 1
    sleep 1
  done
}

smoke_holder_down() {
  docker rm -f "$SMOKE_HOLDER" >/dev/null 2>&1 || true
}

# 子として test:ci を起動し、WireMock が応答してから信号を送る。終了コードを出す。
# Why: 信号の前に WireMock の応答を待つのは、test:ci の trap（INT と TERM）が設定された後に信号を送るため。
# Why 作業場所を分ける: 子の一時物を、リポジトリの .e2e と e2e-logs に出さないため。
smoke_signal_child() { # 信号名 子の作業場所
  python3 -B - "$ROOT" "$1" "$2" "$SMOKE_WORK/child-$1.err" <<'PY'
import os
import signal
import subprocess
import sys
import time
import urllib.request

root, sig_name, e2e_dir, err_path = sys.argv[1:5]
sig = {"INT": signal.SIGINT, "TERM": signal.SIGTERM}[sig_name]
env = dict(os.environ, SWSC_E2E_DIR=e2e_dir, SWSC_LOG_DIR=e2e_dir + "-logs")


def restore_default_signals():
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, signal.SIG_DFL)


with open(err_path, "w") as err:
    proc = subprocess.Popen(["sh", os.path.join(root, "scripts", "e2e.sh"), "test:ci"],
                            env=env, stdout=subprocess.DEVNULL, stderr=err,
                            preexec_fn=restore_default_signals)
    ready = False
    deadline = time.time() + 240
    while time.time() < deadline and proc.poll() is None:
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/__admin/mappings", timeout=2) as resp:
                if resp.status == 200:
                    ready = True
                    break
        except OSError:
            time.sleep(1)
    if ready:
        proc.send_signal(sig)
    try:
        print(proc.wait(timeout=300))
    except subprocess.TimeoutExpired:
        proc.kill()
        print("timeout")
PY
}

# 項目1: start が成功し、起動順が WireMock、pause、Squid で、Squid のログに upstream=mock が出る。
smoke_1() {
  smoke_e2e start >"$TMP/start.out" 2>&1 || {
    cat "$TMP/start.out" >&2
    echo 'start が失敗した'
    return 1
  }
  docker inspect --format '{{.Created}}' swsc-wiremock swsc-pause swsc-squid | python3 -B -c '
import re, sys
from datetime import datetime
ts = []
for line in sys.stdin:
    s = re.sub(r"\.(\d{6})\d*", r".\1", line.strip()).replace("Z", "+00:00")
    ts.append(datetime.fromisoformat(s))
if len(ts) != 3 or not (ts[0] < ts[1] < ts[2]):
    sys.exit("起動順が WireMock、pause、Squid になっていない")
' || return 1
  docker logs swsc-squid 2>&1 | grep -q 'swsc-squid: upstream=mock' || {
    echo 'Squid のログに upstream=mock が無い'
    return 1
  }
}

# 項目2: test の3項目が通り、受信数は /api/ で始まるURLだけを数える（swsc_wiremock_total）。
# 通ったあと、collect で収集する（項目10の確認に使う）。
smoke_2() {
  _rc=0
  smoke_e2e test >"$TMP/test.out" 2>&1 || _rc=$?
  cat "$TMP/test.out" >&2
  [ "$_rc" -eq 0 ] || {
    echo "test の終了コードが $_rc"
    return 1
  }
  [ "$(grep -c '^PASS: ' "$TMP/test.out")" -eq 3 ] || {
    echo 'PASS が3件ではない'
    return 1
  }
  # Why || true: collect は識別情報を削除した回だけ1を返す。その回数は、報告に出して確かめる。
  smoke_e2e collect >"$TMP/collect.out" 2>&1 || true
}

# 項目3: SQUID_UPSTREAM が未設定、または mock と direct 以外の使い捨てのSquidは、非ゼロで終わる。
smoke_3() {
  trap 'docker rm -f m09-smoke-probe-unset m09-smoke-probe-bogus >/dev/null 2>&1 || true' EXIT
  docker rm -f m09-smoke-probe-unset m09-smoke-probe-bogus >/dev/null 2>&1 || true
  docker run -d --name m09-smoke-probe-unset swsc-squid:e2e >/dev/null || return 1
  docker run -d --name m09-smoke-probe-bogus -e SQUID_UPSTREAM=bogus swsc-squid:e2e >/dev/null || return 1
  for _n in m09-smoke-probe-unset m09-smoke-probe-bogus; do
    _rc=$(smoke_probe_exit "$_n" 60) || {
      echo "$_n が止まらない"
      return 1
    }
    [ "$_rc" != 0 ] || {
      echo "$_n の終了コードが0"
      return 1
    }
    docker logs "$_n" 2>&1 | grep -q 'SQUID_UPSTREAM は mock か direct' || {
      echo "$_n に理由が出ていない"
      return 1
    }
  done
}

# 項目4: direct の使い捨てのSquidは、ログに upstream=direct が出て、squid -k parse が通る。外部通信はしない。
smoke_4() {
  trap 'docker rm -f m09-smoke-probe-direct >/dev/null 2>&1 || true' EXIT
  docker rm -f m09-smoke-probe-direct >/dev/null 2>&1 || true
  docker run -d --name m09-smoke-probe-direct -e SQUID_UPSTREAM=direct swsc-squid:e2e >/dev/null || return 1
  _lim=$(($(date +%s) + 60))
  until docker logs m09-smoke-probe-direct 2>&1 | grep -q 'swsc-squid: upstream=direct'; do
    [ "$(date +%s)" -lt "$_lim" ] || {
      echo 'upstream=direct が出ない'
      docker logs m09-smoke-probe-direct >&2 2>&1 || true
      return 1
    }
    sleep 1
  done
  if docker logs m09-smoke-probe-direct 2>&1 | grep -q '失敗'; then
    echo '起動時に失敗が出ている'
    return 1
  fi
  docker exec m09-smoke-probe-direct squid -k parse -f /etc/squid/squid.conf >"$TMP/parse.out" 2>&1 || {
    cat "$TMP/parse.out" >&2
    echo 'squid -k parse が失敗した'
    return 1
  }
}

# 項目5: start の二重実行で成功し、コンテナが重複しない。stop の二重実行は終了コード0。
smoke_5() {
  smoke_e2e start >"$TMP/s5a.out" 2>&1 || return 1
  smoke_e2e start >"$TMP/s5b.out" 2>&1 || {
    cat "$TMP/s5b.out" >&2
    echo '2回目の start が失敗した'
    return 1
  }
  for _n in swsc-wiremock swsc-pause swsc-squid; do
    _c=$(docker ps -a --format '{{.Names}}' | grep -cx "$_n" || true)
    [ "$_c" = 1 ] || {
      echo "$_n が $_c 個ある"
      return 1
    }
  done
  smoke_e2e stop >/dev/null 2>&1 || return 1
  smoke_e2e stop >/dev/null 2>&1 || {
    echo '2回目の stop が非ゼロ'
    return 1
  }
}

# 項目6: 8080 を別のコンテナが使うとき、start と test:ci は非ゼロで終わり、swsc- が残らず、e2e-logs が作られる。
smoke_6() {
  trap smoke_holder_down EXIT
  # Why: e2e-logs は smoke が作る収集先。作られたことを確かめるため、先に消しておく。
  rm -rf "$ROOT/e2e-logs"
  smoke_holder_up || {
    echo '占有者のコンテナが8080で待ち受けない'
    return 1
  }
  _rc=0
  smoke_e2e start >"$TMP/s6-start.out" 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] || {
    echo 'start が占有中に成功した'
    return 1
  }
  _rc=0
  smoke_e2e test:ci >"$TMP/s6-ci.out" 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] || {
    echo 'test:ci が占有中に成功した'
    return 1
  }
  [ -z "$(smoke_swsc_left)" ] || {
    echo 'swsc- が残っている'
    return 1
  }
  [ -d "$ROOT/e2e-logs" ] || {
    echo 'e2e-logs が作られていない'
    return 1
  }
}

# 項目7: swsc- 以外が使用中のとき、start は「swsc- 以外が使用中」として止まり、旧基盤の可能性を示す。
smoke_7() {
  trap smoke_holder_down EXIT
  smoke_holder_up || {
    echo '占有者のコンテナが8080で待ち受けない'
    return 1
  }
  _rc=0
  smoke_e2e start >"$TMP/s7.out" 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] || {
    echo 'start が占有中に成功した'
    return 1
  }
  # shellcheck disable=SC2015 # 意図どおり。2つの grep のどちらかが失敗したら { } で理由を出して失敗させる。A が成功して B が失敗した場合も { } に入る必要がある。
  grep -q 'swsc- 以外' "$TMP/s7.out" && grep -q '旧基盤' "$TMP/s7.out" || {
    cat "$TMP/s7.out" >&2
    echo '止まった理由に「swsc- 以外」と「旧基盤」が無い'
    return 1
  }
}

# 項目8: 子として test:ci を起動し、INT で 130、TERM で 143 になり、swsc- が残らない。一時物の扱いは報告する。
smoke_8() {
  for _pair in INT:130 TERM:143; do
    _sig=${_pair%%:*}
    _want=${_pair##*:}
    _dir=$SMOKE_WORK/child-$_sig
    _rc=$(smoke_signal_child "$_sig" "$_dir") || return 1
    [ "$_rc" = "$_want" ] || {
      echo "$_sig の終了コードが $_rc（期待 $_want）"
      return 1
    }
    [ -z "$(smoke_swsc_left)" ] || {
      echo "$_sig の後に swsc- が残っている"
      return 1
    }
  done
}

# 項目9: stop の後、ラベル付きのコンテナが無く、swsc-net が無い。
smoke_9() {
  smoke_e2e stop >"$TMP/stop.out" 2>&1 || return 1
  [ -z "$(docker ps -aq --filter label=swsc.managed=true)" ] || {
    echo 'stop の後にラベル付きのコンテナが残っている'
    return 1
  }
  [ -z "$(docker network ls --format '{{.Name}}' | grep -x swsc-net || true)" ] || {
    echo 'stop の後に swsc-net が残っている'
    return 1
  }
}

# 項目10: 収集した e2e-logs に、12桁の数字と ARN が無い。
smoke_10() {
  [ -d "$ROOT/e2e-logs" ] || {
    echo 'e2e-logs が無い'
    return 1
  }
  if grep -rEq "$SMOKE_ID_RE" "$ROOT/e2e-logs"; then
    echo 'e2e-logs に識別情報が残っている（行は表示しない）'
    return 1
  fi
}

# 項目11: SQUID_UPSTREAM に不正な値を使った test:ci は非ゼロで終わり、swsc-squid.log が空でない形で作られる。
# Why 写し: 不正な値は本番の描画を通らないため、写しの描画の既定値だけを変える。本番のスクリプトに分岐を入れないため。
smoke_11() {
  _sb=$SMOKE_WORK/item11
  rm -rf "$_sb"
  mkdir -p "$_sb" || return 1
  for _d in scripts ecs squid-config wiremock-scenarios test-client; do
    cp -R "$ROOT/$_d" "$_sb/" || return 1
  done
  cp "$ROOT/Dockerfile.test-client" "$_sb/" || return 1
  # shellcheck disable=SC2016 # sed の式。e2e-lib.sh 内の文字列 $SWSC_LOCAL_SQUID_IMAGE を一致させるため、展開させない。
  sed 's/\$SWSC_LOCAL_SQUID_IMAGE" local mock /$SWSC_LOCAL_SQUID_IMAGE" local bogus /' \
    "$_sb/scripts/e2e-lib.sh" >"$_sb/e2e-lib.tmp" || return 1
  mv "$_sb/e2e-lib.tmp" "$_sb/scripts/e2e-lib.sh" || return 1
  grep -q 'local bogus' "$_sb/scripts/e2e-lib.sh" || {
    echo '写しの上流の値が変わっていない'
    return 1
  }
  _rc=0
  sh "$_sb/scripts/e2e.sh" test:ci >"$TMP/s11.out" 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] || {
    echo 'test:ci が不正な上流で成功した'
    return 1
  }
  [ -s "$_sb/e2e-logs/containers/swsc-squid.log" ] || {
    echo 'swsc-squid.log が作られていない、または空'
    return 1
  }
  [ -z "$(smoke_swsc_left)" ] || {
    echo 'swsc- が残っている'
    return 1
  }
}

# smoke の本体。unit が落ちたら Docker を起動しない。項目は1から11の順。
run_smoke() {
  TMP=$(mktemp -d)
  SMOKE_WORK=$(mktemp -d)
  _had_logs=0
  [ -d "$ROOT/e2e-logs" ] && _had_logs=1
  _had_e2e=0
  [ -d "$ROOT/.e2e" ] && _had_e2e=1
  _t0=$(date +%s)
  trap 'smoke_exit "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  printf '== smoke 前提（unit を先に実行する）\n'
  _u=$SMOKE_WORK/unit.out
  if ! sh "$ROOT/tests/m09-execution-and-ci.sh" unit >"$_u" 2>&1; then
    tail -n 20 "$_u" >&2
    printf 'FAIL: unit が落ちたため、smoke は Docker を起動しない\n' >&2
    return 1
  fi
  tail -n 1 "$_u"

  # Why: swsc- の残りを消してから、8080 を確かめる（自分の残りを他者の占有と誤認しないため）。
  smoke_e2e stop >/dev/null 2>&1 || {
    printf 'FAIL: swsc- の残りを消せない\n' >&2
    return 1
  }
  if smoke_port_busy 8080; then
    printf 'FAIL: ポート8080が使用中。swsc- 以外のコンテナかプロセス（旧基盤の可能性）。止めてから再実行する\n' >&2
    return 1
  fi

  printf '== smoke 項目\n'
  smoke_item 1 '起動の順序と upstream=mock' smoke_1
  smoke_item 2 'test の3項目と受信数' smoke_2
  smoke_item 3 '未設定と不正な上流は非ゼロで終わる' smoke_3
  smoke_item 4 'direct の起動と squid -k parse' smoke_4
  smoke_item 5 '二重の start と stop' smoke_5
  smoke_item 6 '8080の占有で start と test:ci が止まる' smoke_6
  smoke_item 7 '占有の理由に旧基盤を示す' smoke_7
  smoke_item 8 'INT と TERM の終了コードと後始末' smoke_8
  smoke_item 9 'stop の後に残りが無い' smoke_9
  smoke_item 10 'e2e-logs に識別情報が無い' smoke_10
  smoke_item 11 '不正な上流の test:ci の収集順' smoke_11

  _sec=$(($(date +%s) - _t0))
  printf 'smoke: %d 件中 %d 件通過（所要 %d 秒）\n' "$total" "$((total - failures))" "$_sec"
  [ "$failures" -eq 0 ]
}

# 終了時の後始末。失敗時は収集してから止め、成功時だけ自分が作った収集物と一時物を消す。
# Why: 失敗時の収集物は、調べるために残す（plan 5.2）。swsc- のコンテナは、いつも止める（1.2）。
smoke_exit() { # 終了コード
  _rc=$1
  if [ "$_rc" -ne 0 ] || [ "$failures" -ne 0 ]; then
    smoke_e2e collect >/dev/null 2>&1 || true
  fi
  docker rm -f "$SMOKE_HOLDER" m09-smoke-probe-unset m09-smoke-probe-bogus m09-smoke-probe-direct \
    >/dev/null 2>&1 || true
  smoke_e2e stop >/dev/null 2>&1 || true
  if [ "$_rc" -eq 0 ] && [ "$failures" -eq 0 ]; then
    [ "$_had_logs" = 1 ] || rm -rf "$ROOT/e2e-logs"
    [ "$_had_e2e" = 1 ] || rm -rf "$ROOT/.e2e"
  fi
  rm -rf "$SMOKE_WORK" "$TMP"
  exit "$_rc"
}

# contract の本体（plan 5.4）。認証情報を最初に検査し、unit に続けて C1 から C6 を行う。
# Why: 認証情報を unit より先に検査するのは、ダミーが無いときに Docker や AWS に触れないため。
run_contract() {
  if [ -n "${AWS_PROFILE:-}" ] || [ "${AWS_ACCESS_KEY_ID:-}" != test ] || [ "${AWS_SECRET_ACCESS_KEY:-}" != test ]; then
    printf 'FAIL: 認証情報が無い（AWS_ACCESS_KEY_ID と AWS_SECRET_ACCESS_KEY にダミーの test を設定し、AWS_PROFILE は設定しない）\n' >&2
    return 1
  fi
  _u=$(mktemp)
  if ! sh "$ROOT/tests/m09-execution-and-ci.sh" unit >"$_u" 2>&1; then
    cat "$_u" >&2
    rm -f "$_u"
    printf 'FAIL: unit が落ちたため、contract は実行しない\n' >&2
    return 1
  fi
  tail -n 1 "$_u"
  rm -f "$_u"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT

  contract_item C1 '認証情報が未設定なら止まり、MiniStackを作らない' contract_c1
  contract_item C2 '認証情報が test 以外なら止まり、MiniStackを作らない' contract_c2
  contract_item C3 'ダミー認証情報で登録と describe の比較が一致する' contract_c3
  contract_item C4 '保存した inspect に docker.sock が無く、公開は127.0.0.1:4566だけ' contract_c4
  contract_item C5 'contract の終了後に swsc- のコンテナが残らない' contract_c5
  contract_item C6 '完成版の image を変えた写しは compare で不一致になる' contract_c6

  printf 'contract: %d 件中 %d 件通過\n' "$total" "$((total - failures))"
  [ "$failures" -eq 0 ]
}

# MiniStack のコンテナが残っていないか。Why: 名前の完全一致で見る（部分一致で他のコンテナを数えないため）。
contract_no_ministack() {
  [ -z "$(docker ps -a --format '{{.Names}}' | grep -x swsc-ministack || true)" ]
}

contract_c1() {
  _rc=0
  env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_PROFILE sh "$ROOT/scripts/e2e.sh" contract \
    >"$TMP/c1.out" 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] || {
    echo '認証情報なしで contract が成功した'
    return 1
  }
  grep -q '前提不足' "$TMP/c1.out" || {
    echo '前提不足の表示が無い'
    return 1
  }
  contract_no_ministack || {
    echo 'swsc-ministack が作られた'
    return 1
  }
}

contract_c2() {
  _rc=0
  env -u AWS_PROFILE AWS_ACCESS_KEY_ID=other AWS_SECRET_ACCESS_KEY=test \
    sh "$ROOT/scripts/e2e.sh" contract >"$TMP/c2.out" 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] || {
    echo 'test 以外の認証情報で contract が成功した'
    return 1
  }
  contract_no_ministack || {
    echo 'swsc-ministack が作られた'
    return 1
  }
}

contract_c3() {
  sh "$ROOT/scripts/e2e.sh" contract >"$TMP/c3.out" 2>&1 || {
    cat "$TMP/c3.out" >&2
    echo 'ダミー認証情報の contract が失敗した'
    return 1
  }
}

contract_c4() { # [inspectのファイル]
  python3 -B - "${1:-$ROOT/.e2e/ministack-inspect.json}" <<'PY' || {
import json
import sys

d = json.load(open(sys.argv[1], encoding="utf-8"))
mounts = d.get("Mounts") or []
if any("docker.sock" in str(m.get("Source", "")) + str(m.get("Destination", "")) for m in mounts):
    sys.exit("docker.sock が渡っている")
# Why: イメージが EXPOSE しただけのポート（実機の MiniStack 1.5.37 では 2222/tcp）は、値が null で載る。
# 公開されているポートだけを数えるため、バインドを持つものに絞る。
ports = {k: v for k, v in (d.get("Ports") or {}).items() if v}
if list(ports.keys()) != ["4566/tcp"]:
    sys.exit("公開ポートが4566/tcpだけではない")
if [b.get("HostIp") for b in ports["4566/tcp"]] != ["127.0.0.1"]:
    sys.exit("公開先が127.0.0.1だけではない")
PY
    echo 'inspect の保存内容が条件を満たさない'
    return 1
  }
}

contract_c5() {
  [ -z "$(docker ps -aq --filter label=swsc.managed=true)" ] || {
    echo 'contract の後に swsc- のコンテナが残っている'
    return 1
  }
}

# 完成版の image を1か所変えた写しを、実機の describe と比べ、不一致で非ゼロになることを確かめる。
contract_c6() {
  python3 -B - "$ROOT/.e2e/taskdef.json" "$TMP/taskdef-changed.json" <<'PY' || return 1
import json
import sys

d = json.load(open(sys.argv[1], encoding="utf-8"))
d["containerDefinitions"][0]["image"] += "-changed"
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"))
PY
  _rc=0
  python3 -B "$ROOT/scripts/e2e-taskdef.py" compare --report "$TMP/c6-report.json" \
    "$TMP/taskdef-changed.json" "$ROOT/.e2e/ministack-describe.json" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -ne 0 ] || {
    echo '写しの image の変更を compare が検出しない'
    return 1
  }
}

# ---------------------------------------------------------------------------
# T915: CIワークフロー（.github/workflows/e2e-test.yml）の静的検査。
# 検査は yq（mikefarah/yq、mise which の実体）で YAML を構造比較する。PyYAML は使わない。
# Why: CI の実行は GitHub 上でしか確かめられないため、手元では設定の取り違えを静的に固定する。
# ---------------------------------------------------------------------------

WF=$ROOT/.github/workflows/e2e-test.yml

# yq の実体を出す。mise の自動導入を止めて mise which で得る。得られなければ失敗する（mise exec は使わない）。
# Why: PATH 上の別の yq を使わないため（clarify.md 3章、R01 と同じ方針）。
wf_yq_bin() {
  _y=$(cd "$ROOT" && MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise which yq 2>/dev/null) || return 1
  [ -x "$_y" ] || return 1
  printf '%s\n' "$_y"
}

# T2631: shellcheck の設定（.shellcheckrc）と mise の設定（mise.toml）を、必要な行だけに制限する。
# Why: 設定に disable や [tasks]、[hooks]、[env] があると、検査の緩みや任意の実行を、レビューなしに持ち込めるため。
# T2632: mise.toml は min_version と [tools] の6ツール（shellcheck、actionlint、gitleaks、bats、jq、yq）だけを持つ。
# Why: [tasks]、[hooks]、[env]、[plugins] は任意の実行や環境の書き換えを持ち込むため、レビューなしに入れない。
# T2622: M08 の4シナリオは test-ci の検査列に直列で入る。専用の step は増やさない（ステップの順序は変えない）。
# 壊した定義1件を一時ファイルへ作り、対応する検査が落ちることを確かめる。
wf_broken_case() { # 件名 sedの式 検査の関数
  # shellcheck disable=SC2154 # _wf_broken_dir は、この関数を呼ぶ bats の検査（tests/bats/m09-execution-and-ci.bats）が設定する
  _f=$_wf_broken_dir/$1.yml
  sed -e "$2" "$WF" >"$_f" || return 1
  # 壊し方が効いていなければ、検査が落ちても意味が無いため失敗にする。
  if diff -q "$WF" "$_f" >/dev/null 2>&1; then return 1; fi
  # 検査は部分シェルで、WF を一時ファイルへ向けて読む。リポジトリのワークフローは変えない。
  # shellcheck disable=SC2030 # WF の変更は部分シェルの中だけに閉じる。意図どおり、親の WF は変えない。
  if (WF=$_f; "$3") >/dev/null 2>&1; then return 1; fi
  return 0
}

# T2633: 7.4節の壊した定義の10件を、一時ファイルで作り、対応する検査が落ちることを確かめる。
# Why: 検査が壊れた定義を見ずに通ってしまうことを防ぐため。判定は yq の構造比較の検査で行う。
# Why: 作業ファイルは $KIROCREW_SCRATCH（無ければ $TMPDIR か /tmp）の mktemp -d の下に置き、検査の終わりに1つずつ消す。
# T2634: actionlint は式の誤りで失敗し、現在のワークフローでは成功する（永続する回帰検査）。
# Why: actionlint が式を読めなくなると、CI の静的検査が何も止めないまま通るため。
# ---------------------------------------------------------------------------
# T916 文書（docs/ローカル実行とCI.md、README.md、AGENTS.md）
# Why: 文書は利用者とCIの入口になるため、節、リンク、識別情報の不在、既存の行の保持を固定する。
# ---------------------------------------------------------------------------
# S26 T2630: Compose の削除とともに、README の旧 Compose 手順も削除した。現行の手順だけを載せる。
# ---------------------------------------------------------------------------
# T917: 品質ゲートへの登録（unit と smoke。contract は登録しない）
# ---------------------------------------------------------------------------

# Why: ゲートへの登録は、ゲートのスクリプトの行で静的に確かめる。実行の結果は unit と smoke が確かめる。
gate_has() { # 文字列 部分文字列
  printf '%s\n' "$1" | grep -Fq -- "$2"
}

# M09 のブロック（scripts/e2e の対象を判定する if から、対応する column 0 の fi まで）を出す。
gate_m09_block() {
  _gf=$ROOT/scripts/quality-gate.sh
  _gif=$(grep -n "^if has_match '.*scripts/e2e" "$_gf" | cut -d: -f1)
  [ -n "$_gif" ] || return 1
  awk -v s="$_gif" 'NR >= s { print } NR > s && /^fi$/ { exit }' "$_gf"
}

# 共通の関数（`resolve_tool`）は `scripts/lib/resolve-tool.sh` にあるため、2つを探す（plan 4.2 節）。
gate_sources() { cat "$ROOT/scripts/quality-gate.sh" "$ROOT/scripts/lib/resolve-tool.sh"; }

# T2631: 品質ゲートの shellcheck は、mise which の実体を、版を比べて、自動の導入を止めて実行する。
# Why: PATH 上の別の shellcheck や、mise exec による導入に頼ると、ゲートの結果が環境で変わるため。
# T2633: 品質ゲートは actionlint と yq の実体を mise which で得て、自動の導入を止める3つの環境変数を各行に付ける。
# Why: 版の固定を、PATH や mise exec の自動導入に任せると、ゲートの結果が環境で変わるため。
# T-R0254: 品質ゲートは、JSON を扱う検査より前に、jq の実体と版を確かめる。
# Why: jq を先頭で照合しないと、未導入や版違いが後段の JSON の検査の途中で、分かりにくい失敗として現れるため。
# T-R0274: bats の偽の docker、aws などの用意（make_base_bin など4つ）は、
# tests/bats/helpers/fakes.bash の1か所だけで定義する。
# T-R0274: 旧の入口 tests/lib/run-bats.sh は、引数の数とモードを検査し、不正なら終了コード2で止まる。
# T-R0274: 品質ゲートは、JSON や YAML の検査より前に、bats の実体と版を確かめる。
# T-R0274: M02〜M09 の実行条件は、対応する tests/bats/<名前>.bats の変更でも走り、
# tests/bats/helpers/ と tests/lib/run-bats.sh の変更は、このゲートの対象に入る。
# swsc_count_api_requests（jq）は、接頭辞 /api/ の URL だけを数える。固定の入力で件数を確かめる。
# T-R0253: JSON の値の取り出しは jq に置き換える（plan 9.2 節）。Python の json.load を残してよいのは、
# JSON を書き換える mutate() の中だけである。取り出しではなく、壊した入力や変更後の JSON を作るための経路だから。
# Why: m03 と m07 の取り出しを、jq へ移したことを、json.load の不在で確かめる。
# T-R0235: .gitleaks.toml は独自の規則だけを持ち、既定の規則の読み込み（useDefault）、
# トップレベルの [allowlist]、stopwords を書かない。コメントの中の語は対象外。
# Why: 既定の規則や全体の除外は、置き換え前の検査の範囲を黙って狭めるため（clarify.md 7章）。
# gitleaks dir を1つのディレクトリに走らせ、終了コードを標準出力へ出す。出力は指定のファイルへ書く。
gl_scan_rc() { # 実体 設定 走査するディレクトリ 出力先
  _rc=0
  "$1" dir "$3" --config "$2" --redact --no-banner --exit-code 1 >"$4" 2>&1 || _rc=$?
  printf '%s\n' "$_rc"
}

# 値の検出を確かめる。終了コードが0なら失敗、出力に値が出ていれば失敗（値を出さないことの確認）。
gl_expect_detect() { # 実体 設定 走査先 出力先 値
  _rc=$(gl_scan_rc "$1" "$2" "$3" "$4")
  [ "$_rc" -ne 0 ] || return 1
  grep -qF -- "$5" "$4" && return 1
  return 0
}

# 値の形に合わない語だけのファイルは、終了コードが0になることを確かめる。
gl_expect_clean() { # 実体 設定 走査先 出力先
  _rc=$(gl_scan_rc "$1" "$2" "$3" "$4")
  [ "$_rc" -eq 0 ]
}

# 検査が作った一時ディレクトリを消す。中のファイルを1つずつ rm -f し、ディレクトリを深い順に rmdir する。
# 作業ディレクトリの名前が gitleaks- で始まらないときは、何も消さずに失敗する（別の場所を消さないため）。
gl_cleanup() { # 作業ディレクトリ
  case "$(basename "$1")" in gitleaks-*) ;; *) return 1 ;; esac
  [ -d "$1" ] || return 1
  _cr=0
  find "$1" -type f -exec rm -f {} \; || _cr=1
  find "$1" -depth -type d -exec rmdir {} \; || _cr=1
  return "$_cr"
}

# T-R0347: gitleaks の段2（値の形に絞った3規則）が、実行時に組み立てた値を検出し、値を出力しないことを確かめる。
# Why: 規則が効かなくなると、識別情報を含む変更が品質ゲートを通ってしまうため。
# 値は printf の引数で連結して作り、ファイルに固定の値として書かない（NFR-R0206）。
# 段1（path に限る規則）は、一時ディレクトリの相対パスに当たるかが未確認のため、この検査の対象にしない。段1は手動確認（T-R0343、T-R0246）に残す。
# T-R0348: 段1の path 規則が、FR-R0210 の11ファイルに12桁の番号を検出し、対象外のパスには検出しないことを確かめる。
# Why: path 規則の範囲が狭まると、置き換え前の検査の範囲を黙って失うため（FR-R0210）。
# gitleaks は絶対パスで File を書くため、一時ディレクトリの中へ移り、相対パスで走査する。
# 値は printf で組み立て、ファイルに固定で書かない（NFR-R0206）。検出の出力は JSON で読み、値を表示しない。
# 段1の3規則（identity-doc の id を持つ規則）の path は、3つとも同じ文字列であることを確かめる。
# Why: 3規則の path がずれると、一部の規則だけ対象のファイルが狭まり、検出の範囲を黙って失うため。
# T2621: Compose の項目を外し、管理対象の残存検査（swsc_check_managed_empty）へ置き換えた品質ゲートの検査。
# 品質ゲートの managed_check を、ゲートの定義から取り出して実行する。偽の docker の失敗が status=1 になることを確かめる。
# T2621: M02 は稼働中のスタックを前提にしなくなったため、ゲートの対象へ入れ、除外の NOTE を外す。
# T2601: ロックとポート確認の検査。ロックは実行専用の一時ディレクトリだけに置く。
# Why: 実ホストの既定のロック（/tmp/swsc-e2e-ports.lock）を検査が作ると、利用中のロックと衝突するため。
lock_case_dir() {
  # Why: $TMP の中に置かない。check が検査ごとに $TMP の中身を消すため、全体用の置き場まで消え、
  # 次の find が失敗して unit が止まる（KIROCREW_SCRATCH の無い CI で発生。手元では隠れていた）。
  _lb=${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}
  mkdir -p "$_lb" || return 1
  mktemp -d "$_lb/swsc-lock-case.XXXXXX"
}

# 検査の後始末。rm -rf を使わず、検査が作った中身だけを消してから空の場所を消す。
lock_case_clear() { # ディレクトリ
  find "$1" -mindepth 1 -delete
  rmdir "$1"
}

# T2602: Client の環境変数、WireMock の path 件数、Squid のログ検査。
# Why: 偽の docker と curl を、検査専用の一時ディレクトリだけに置き、実の Docker と WireMock に触れないようにする。
# 偽の経路の置き場に、危ない命令の保護用の偽物を置く。PATH の後ろにある実環境の同名の命令へ届かないようにする。
# Why: PATH="$_bin:$PATH" のままだと、偽物が無い命令は実環境の docker、curl、aws、ssh へ届くため。
# 偽物は、この後で各ヘルパーが同じ名前で上書きする。
t2602_guard_bin() { # 置き場
  mkdir -p "$1"
  for _n in docker docker-compose curl aws ssh; do
    cat >"$1/$_n" <<'EOF'
#!/bin/sh
# このテストに無い命令が呼ばれたら止める。終了コード97で、実環境の同名の命令は動かさない。
printf 'blocked by test: %s %s\n' "$0" "$*" >&2
exit 97
EOF
    chmod +x "$1/$_n"
  done
}

t2602_fake_docker() { # 置き場
  mkdir -p "$1"
  t2602_guard_bin "$1"
  cat >"$1/docker" <<'EOF'
#!/bin/sh
# 呼ばれた引数を1行1要素で記録する。Why: 空白や引用符を含む値が、分かれずに1要素で届いたかを見るため。
for _a in "$@"; do
  printf '[%s]\n' "$_a"
done >>"$SWSC_FAKE_REC"
if [ "$1" = exec ]; then
  if [ -n "${SWSC_FAKE_EXEC_FAIL:-}" ]; then
    echo 'Error: no such container' >&2
    exit 1
  fi
  cat "$SWSC_FAKE_LOG"
  exit 0
fi
echo client-stdout
echo client-stderr >&2
exit "${SWSC_FAKE_RC:-0}"
EOF
  chmod +x "$1/docker"
}

t2602_fake_curl() { # 置き場
  mkdir -p "$1"
  t2602_guard_bin "$1"
  cat >"$1/curl" <<'EOF'
#!/bin/sh
# 応答ファイルの中身を返す。SWSC_FAKE_CURL_FAIL があれば、接続失敗と同じ終了コードで止まる。
if [ -n "${SWSC_FAKE_CURL_FAIL:-}" ]; then
  exit 22
fi
cat "$SWSC_FAKE_BODY"
EOF
  chmod +x "$1/curl"
}

# T2603: 管理対象の残存検査と、runner のラベル。
# 偽の docker は、ラベルで絞った呼び出しと絞らない呼び出しで、返す一覧を変える。
# Why: 実 docker は label で絞るため、絞らなかった一覧との差で、絞り込みの漏れを検出するため。
managed_setup() {
  mkdir -p "$TMP/mbin"
  cat >"$TMP/mbin/docker" <<'FAKE'
#!/bin/sh
echo "docker $*" >>"$SWSC_TEST_DIR/rec-docker"
if [ -f "$SWSC_TEST_DIR/docker-fail" ]; then exit 1; fi
case "$*" in
  *label=swsc.managed=true*) _lab=1 ;;
  *) _lab=0 ;;
esac
case "$1" in
  ps) if [ "$_lab" = 1 ]; then cat "$SWSC_TEST_DIR/lab-ps" 2>/dev/null; else cat "$SWSC_TEST_DIR/all-ps" 2>/dev/null; fi ;;
  network) if [ "$_lab" = 1 ]; then cat "$SWSC_TEST_DIR/lab-net" 2>/dev/null; else cat "$SWSC_TEST_DIR/all-net" 2>/dev/null; fi ;;
esac
exit 0
FAKE
  chmod +x "$TMP/mbin/docker"
  make_base_bin "$TMP/mbase"
}

# 残存検査の関数を、偽の docker を入れた PATH で評価する。
managed_run() { # 本体
  # shellcheck disable=SC2016 # 単一引用符の中の $1 と $SWSC_ROOT は、env -i で起動した子の sh が展開する。eval で与えた文を子で評価する意図。
  env -i PATH="$TMP/mbin:$TMP/mbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_TEST_DIR="$TMP" \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; eval "$1"' sh "$1"
}

# T2603: 入口のロックと trap。ロックは検査専用の場所（UNIT_LOCK）にだけ作る。
# Why: 実ホストの /tmp/swsc-e2e-ports.lock を検査が取ると、利用中の実行と衝突するため。
# 他者のロックは、取り残しを模して owner を書いた mkdir で作る。
lock_busy_setup() {
  mkdir "$UNIT_LOCK" || return 1
  printf '%s\n%s\n' 99999 other >"$UNIT_LOCK/owner"
}

# stop、clean、logs は、ロックが残っていても動き、ロックには触れない。
run_unit() {
  # jq の実体は、固定版を照合して得る（JSON の値の取り出しに使う）。未導入や版違いは、ここで導入手順つきに止まる。
  # Why: unit だけが使う。contract の検査は認証情報の無い環境で止まる必要があるため、入口では照合しない。
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/resolve-tool.sh"
  resolve_tool jq 's/^jq-//p' --version || exit 1
  jq_bin=$RESOLVED_PATH
  # Why: 検査の sandbox は PATH を絞るため mise が見えない。照合済みの jq を、同じ版として引き継ぐ。
  # swsc_jq は SWSC_JQ が設定されていれば照合しない（scripts/e2e-lib.sh）。
  SWSC_JQ=$jq_bin
  export SWSC_JQ
  TMP=$(mktemp -d)
  # Why: 検査ごとに空にする検査専用のロック置き場。実ホストの既定のロックを使わないため。
  UNIT_LOCK_BASE=$(lock_case_dir) || exit 1
  UNIT_LOCK=$UNIT_LOCK_BASE/ports.lock
  trap 'rm -rf "$TMP"; lock_case_clear "$UNIT_LOCK_BASE"' EXIT
  printf '== T907 入口の骨格と前提検査\n'
  printf '== T908 テンプレートと生成\n'
  printf '== T909 本番向けの検査\n'
  printf '== T910 Squid のイメージ\n'
  printf '== T911 MiniStackの契約検証\n'
  printf '== T912 pause方式のランナー\n'
  printf '== T913 入口の完成\n'
  printf '== T914 実通信の検査（smoke と contract のモード）\n'
  printf '== T915 CIワークフロー（静的検査）\n'
  printf '== T916 文書（docs/ローカル実行とCI.md、README.md、AGENTS.md）\n'
  printf '== T917 品質ゲートへの登録\n'
  printf '== T2601 ロックとポート確認\n'
  printf '== T2602 Client環境変数、件数、ログ\n'
  printf '== T2603 管理対象の残存検査とラベル\n'
  printf '== T2603 入口のロックと trap（entry_trap_exit_143）\n'


  # 群1と群2（静的な検査）は bats で行う（T-R0318、T-R0319）。件数は bats の @test の数で数える。
  _g1="$ROOT/tests/bats/m09-execution-and-ci.bats"
  _g1_n=$(grep -c '^@test' "$_g1")
  total=$((total + _g1_n))
  if ! sh "$ROOT/tests/lib/run-bats.sh" "$_g1" unit; then
    failures=$((failures + 1))
    printf 'FAIL: 静的な検査（群1、bats）。詳細は上の bats の出力\n' >&2
  fi
}

if [ "${M09_LIB_ONLY:-}" != 1 ]; then
case $MODE in
    unit)
      run_unit
      printf 'unit: %d 件中 %d 件通過\n' "$total" "$((total - failures))"
      [ "$failures" -eq 0 ]
      ;;
    smoke)
      run_smoke
      ;;
    contract)
      run_contract || exit 1
      ;;
  esac
fi
