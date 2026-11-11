# shellcheck shell=sh
# M09 の入口と bats の検査が共有する補助（失敗の止め方、終了コードの比較、検査の1件の実行）。
# tests/m09-execution-and-ci.sh が . で読む。読み込みに副作用は無い（TMP、total、failures の初期化を除く）。
# Why: 補助を1か所にまとめ、入口に同じ定義を2つ残さないため。

# 検査が一時ファイルを置く場所（run_unit が mktemp -d で作る）と、検査の件数。
# Why: check と must が、同じ作業場所と集計を共有するため。
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

# 入口を、環境変数を外した状態で起動する。Why: 利用者の AWS 設定が検査に混ざるのを防ぐため。
run_e2e() { # PATH 操作...
  _p=$1
  shift
  env -i PATH="$_p" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_JQ="$SWSC_JQ" sh "$ROOT/scripts/e2e.sh" "$@"
}

# e2e-lib.sh と e2e-runner.sh を読み込んだ子シェルで、与えた文を評価する。関数の差し替えに使う。
lib_call() { # 文
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、子の sh が環境変数から展開する。親のシェルでは展開させない意図。 子の sh が SWSC_ROOT から e2e-lib.sh と e2e-runner.sh を読み、eval で与えた文を評価する。
  # shellcheck disable=SC2031 # SWSC_JQ は run_unit で一度だけ設定し、以後は変えない。子の sh に渡すだけの読み取り。
  env -i PATH="$TMP/efake:$TMP/ebase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_E2E_DIR="$TMP/e2e" \
    SWSC_LOG_DIR="$TMP/logs" SWSC_TEST_DIR="$TMP" SWSC_TEST_SEQ="$TMP/seq.log" SWSC_WAIT_SECONDS=2 SWSC_JQ="$SWSC_JQ" \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; . "$SWSC_ROOT/scripts/e2e-runner.sh"; eval "$1"' sh "$1"
}

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

# Why: ゲートへの登録は、ゲートのスクリプトの行で静的に確かめる。実行の結果は unit と smoke が確かめる。
gate_has() { # 文字列 部分文字列
  printf '%s\n' "$1" | grep -Fq -- "$2"
}

# 共通の関数（`resolve_tool`）は `scripts/lib/resolve-tool.sh` にあるため、2つを探す（plan 4.2 節）。
gate_sources() { cat "$ROOT/scripts/quality-gate.sh" "$ROOT/scripts/lib/resolve-tool.sh"; }

# M09 のブロック（scripts/e2e の対象を判定する if から、対応する column 0 の fi まで）を出す。
gate_m09_block() {
  _gf=$ROOT/scripts/quality-gate.sh
  _gif=$(grep -n "^if has_match '.*scripts/e2e" "$_gf" | cut -d: -f1)
  [ -n "$_gif" ] || return 1
  awk -v s="$_gif" 'NR >= s { print } NR > s && /^fi$/ { exit }' "$_gf"
}

# docker-compose の呼び出しを、コマンドの位置で探す（コメントは対象外）。
fr920_hits() { # ファイル...
  grep -hE '(^|[;&|(:-])[[:space:]]*docker[- ]compose([[:space:]]|$)' "$@" 2>/dev/null || true
}

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

render_production() { # 出力先 上流
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render --template "$ROOT/ecs/task-definition.template.json" \
    --out "$1" --client-image swsc-client:prod --squid-image swsc-squid:prod \
    --profile production --upstream "$2"
}

check_production() { # ファイル
  python3 -B "$ROOT/scripts/e2e-taskdef.py" check-production "$1"
}

# 派生を1回走らせる。引数: 上流 出力先 [元ファイル] [ホスト] [ポート]。環境変数は外して渡す。
derive() {
  _src=${3:-$ROOT/squid-config/squid.conf}
  env -i PATH=/usr/bin:/bin SQUID_UPSTREAM="$1" SQUID_MOCK_HOST="${4-swsc-wiremock}" \
    SQUID_MOCK_PORT="${5-8080}" sh "$ROOT/ecs/squid/derive-config.sh" "$_src" "$2"
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

# 完成版の一部を書き換えた写しを作る（d は完成版の辞書）。
runner_mutate() { # Python の文
  python3 -B -c "import json, sys
d = json.load(open(sys.argv[1]))
$1
json.dump(d, open(sys.argv[2], 'w'))" "$TMP/taskdef.json" "$TMP/bad.json"
}

# 記録の中で、固定の文字列を含む最初の行番号を返す。無ければ空。
seq_line() { # 文字列
  grep -n -F -- "$1" "$TMP/seq.log" 2>/dev/null | head -1 | cut -d: -f1 || true
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

runner_docker_args() { # 完成版 出力先
  python3 -B "$ROOT/scripts/e2e-taskdef.py" docker-args --taskdef "$1" --out-dir "$2" \
    --pause-name swsc-pause --run-id 4242
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

contract_item() { # 番号 名前 関数
  check "$1 $2" "$3"
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

# T2603: 入口のロックと trap。ロックは検査専用の場所（UNIT_LOCK）にだけ作る。
# Why: 実ホストの /tmp/swsc-e2e-ports.lock を検査が取ると、利用中の実行と衝突するため。
# 他者のロックは、取り残しを模して owner を書いた mkdir で作る。
lock_busy_setup() {
  mkdir "$UNIT_LOCK" || return 1
  printf '%s\n%s\n' 99999 other >"$UNIT_LOCK/owner"
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
