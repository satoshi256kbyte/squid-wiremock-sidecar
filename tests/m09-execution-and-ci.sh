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

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# SIGINT が無視されたまま起動された場合は、INT の検査が原因の分かりにくい形で落ちるため、先に止める。
# Why: 背景（&）や nohup で起動すると、シェルは SIGINT を無視して始まり、シェルの中から trap で受けられない（POSIX）。
# Why not: 検査の中で無視を解除する方式は採らない。無視された状態を戻せるシェルは無いため。
if [ "$MODE" != contract ]; then
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

# 必要なツールだけを束ねたPATHを作る。docker、aws、docker-compose は含めない。
make_base_bin() { # 出力先
  mkdir -p "$1"
  for _t in sh env python3 curl grep sed awk cat cp mv rm rmdir mkdir chmod cmp diff sort head tail tr wc dirname basename ls find mktemp sleep date; do
    _p=$(command -v "$_t" 2>/dev/null || true)
    case $_p in
      /*) ln -sf "$_p" "$1/$_t" ;;
    esac
  done
  # Why: python3 を mise のシムのまま使うと、HOME を空の一時ディレクトリにした検査の中で、
  # 毎回 Python を取得し直して約18秒かかる。導入済みの実体を指すようにする。
  _real=$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null || true)
  case $_real in
    /*) ln -sf "$_real" "$1/python3" ;;
  esac
}

# 呼ばれたら引数を記録して成功する偽物を作る。
make_fake() { # 名前 置き場 記録先
  mkdir -p "$2"
  printf '#!/bin/sh\necho "%s $*" >>"%s"\nexit 0\n' "$1" "$3" >"$2/$1"
  chmod +x "$2/$1"
}

# 偽の docker、aws、docker-compose を入れたPATHを作る（記録は $TMP/rec-*）。
make_shims() { # 置き場
  make_fake docker "$1" "$TMP/rec-docker"
  make_fake aws "$1" "$TMP/rec-aws"
  make_fake docker-compose "$1" "$TMP/rec-compose"
}

no_calls() { # 記録が空、または無いこと
  for _f in "$TMP"/rec-*; do
    [ ! -e "$_f" ] || [ ! -s "$_f" ] || return 1
  done
  return 0
}

# 入口を、環境変数を外した状態で起動する。Why: 利用者の AWS 設定が検査に混ざるのを防ぐため。
run_e2e() { # PATH 操作...
  _p=$1
  shift
  env -i PATH="$_p" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_JQ="$SWSC_JQ" sh "$ROOT/scripts/e2e.sh" "$@"
}

# ---------------------------------------------------------------------------
# T907: 入口の骨格と前提検査
# ---------------------------------------------------------------------------

t_usage_rejects_bad_arguments() {
  must rc_is 2 sh "$ROOT/tests/m09-execution-and-ci.sh" bogus
  must rc_is 2 sh "$ROOT/tests/m09-execution-and-ci.sh" unit extra
}

t_package_json_delegates_six_scripts() {
  # shellcheck disable=SC2016 # 単一引用符の中の $s、$k は jq の変数であり、シェルで展開させない。
  must "$jq_bin" -e '
    .scripts as $s
    | (["start", "test", "logs", "stop", "clean", "test:ci"]
        | all(. as $k | $s[$k] == ("sh scripts/e2e.sh " + $k)))
      and ($s | has("lint:md"))
  ' "$ROOT/package.json" >/dev/null
}

t_gitignore_hides_run_outputs() {
  must grep -qx '\.e2e/' "$ROOT/.gitignore"
  must grep -qx 'e2e-logs/' "$ROOT/.gitignore"
}

t_entry_without_operation_exits_2() {
  make_base_bin "$TMP/base"
  must rc_is 2 run_e2e "$TMP/base"
}

t_entry_unknown_operation_exits_2() {
  make_base_bin "$TMP/base"
  must rc_is 2 run_e2e "$TMP/base" bogus
}

# S26 T2616: test:ci のシナリオ名は、ロックと docker の前に検査する。不明な名前は終了コード2。
t_test_ci_unknown_scenario_exits_2_before_docker() {
  make_base_bin "$TMP/base"
  make_shims "$TMP/shim"
  _r=0
  run_e2e "$TMP/shim:$TMP/base" test:ci normal bogus >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 2 ]
  must grep -q '不明なシナリオ: bogus' "$TMP/err"
  # docker の呼び出しは、前提検査（docker info など）以外に無いこと。
  if [ -s "$TMP/rec-docker" ]; then
    must sh -c "! grep -Eq 'docker (run|rm|build|network|ps)' '$TMP/rec-docker'"
  fi
  must [ ! -e "$UNIT_LOCK" ]
}

# S26 T2616: test:ci の名前指定。子の終了コードを返し、ロックを解放する。
t_test_ci_scenarios_returns_child_rc_and_releases_lock() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、lib_call（env -i で起動した子の sh の eval）で展開する。親のシェルでは展開させない意図。 $SWSC_LOCK_HELD と $SWSC_TEST_SEQ は子の関数内で使う。
  lib_call 'swsc_test_ci_scenarios_child() { [ "$SWSC_LOCK_HELD" = 1 ] && [ -d "$SWSC_LOCK_DIR" ] && echo "child $*" >>"$SWSC_TEST_SEQ"; return 3; }
swsc_test_ci_scenarios normal slow-5000' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 3 ]
  must seq_is 'child normal slow-5000'
  must [ ! -e "$UNIT_LOCK" ]
}

# S26 T2616: 親だけが TERM を受けても、子へ TERM を送り、子の後始末を待ってからロックを解放する。
t_test_ci_scenarios_term_stops_child_and_releases_lock() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、lib_call（env -i で起動した子の sh の eval）で展開する。親のシェルでは展開させない意図。 trap の中の $SWSC_TEST_SEQ と $SWSC_LOCK_DIR は、子の sh が trap を実行するときに展開する。
  lib_call 'swsc_test_ci_scenarios_child() {
  trap '"'"'echo child-term >>"$SWSC_TEST_SEQ"; [ -d "$SWSC_LOCK_DIR" ] && echo lock-held >>"$SWSC_TEST_SEQ"; exit 143'"'"' TERM
  echo child-start >>"$SWSC_TEST_SEQ"
  kill -TERM "$PPID_PARENT"
  i=0; while [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  echo child-not-stopped >>"$SWSC_TEST_SEQ"
}
PPID_PARENT=$$
swsc_test_ci_scenarios normal' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 143 ]
  must seq_is "$(printf 'child-start\nchild-term\nlock-held')"
  must [ ! -e "$UNIT_LOCK" ]
}

t_logs_accepts_extra_arguments() {
  # docker を外したPATHで、引数の誤りではなく前提の不足（終了コード1）で止まることを確かめる。
  make_base_bin "$TMP/base"
  _r=0
  run_e2e "$TMP/base" logs squid -f >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must grep -q 'docker' "$TMP/err"
}

t_start_without_docker_names_docker() {
  make_base_bin "$TMP/base"
  _r=0
  run_e2e "$TMP/base" start >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must grep -q 'docker' "$TMP/err"
}

t_contract_without_credentials_stops_before_docker_and_aws() {
  mkdir -p "$TMP/shim"
  make_base_bin "$TMP/base"
  make_shims "$TMP/shim"
  _r=0
  env -i PATH="$TMP/shim:$TMP/base" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_JQ="$SWSC_JQ" sh "$ROOT/scripts/e2e.sh" contract \
    >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must grep -q 'AWS_ACCESS_KEY_ID' "$TMP/err"
  must no_calls
}

t_contract_rejects_non_dummy_credentials() {
  mkdir -p "$TMP/shim"
  make_base_bin "$TMP/base"
  make_shims "$TMP/shim"
  _r=0
  env -i PATH="$TMP/shim:$TMP/base" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_JQ="$SWSC_JQ" \
    AWS_ACCESS_KEY_ID=other AWS_SECRET_ACCESS_KEY=test \
    sh "$ROOT/scripts/e2e.sh" contract >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must no_calls
}

t_contract_rejects_aws_profile() {
  mkdir -p "$TMP/shim"
  make_base_bin "$TMP/base"
  make_shims "$TMP/shim"
  _r=0
  env -i PATH="$TMP/shim:$TMP/base" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" \
    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_PROFILE=dev \
    sh "$ROOT/scripts/e2e.sh" contract >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must grep -q 'AWS_PROFILE' "$TMP/err"
  must no_calls
}


t_only_swsc_aws_calls_aws() {
  # 「aws」をコマンドとして呼ぶ行は、scripts/e2e*.sh の中で1行だけでなければならない（swsc_aws）。
  _n=$(grep -hE '(^|[;&|(])[[:space:]]*(env [^;]*)?aws[[:space:]]' "$ROOT"/scripts/e2e*.sh |
    grep -vc '^[[:space:]]*#' || true)
  must [ "$_n" -eq 1 ]
  must grep -q 'swsc_aws()' "$ROOT/scripts/e2e-lib.sh"
}

# docker-compose の呼び出しを、コマンドの位置で探す（コメントは対象外）。
fr920_hits() { # ファイル...
  grep -hE '(^|[;&|(:-])[[:space:]]*docker[- ]compose([[:space:]]|$)' "$@" 2>/dev/null || true
}

t_fr920_detector_catches_command_forms() {
  printf 'docker compose up -d\n' >"$TMP/a.sh"
  printf 'true && docker-compose up\n' >"$TMP/b.sh"
  # shellcheck disable=SC2016 # 書き出すスクリプトの本文として $( ) を文字通り書く。fr920_hits がこの形を検出するかを確かめるため、ここでは展開させない。
  printf 'x=$(docker compose ps)\n' >"$TMP/c.sh"
  printf '    run: docker-compose down\n' >"$TMP/d.yml"
  for _f in a.sh b.sh c.sh d.yml; do
    must [ -n "$(fr920_hits "$TMP/$_f")" ]
  done
}

t_fr920_detector_allows_comments_and_words() {
  printf '# 旧基盤（docker-compose）の説明\necho "docker"\n' >"$TMP/ok.sh"
  must [ -z "$(fr920_hits "$TMP/ok.sh")" ]
}

t_fr920_holds_for_m09_files() {
  _files=$(cd "$ROOT" && ls scripts/e2e*.sh ecs/*/* ecs/*.json .github/workflows/e2e-test.yml package.json 2>/dev/null || true)
  # Why: 対象のパスは位置引数に1つずつ積む。$ROOT に空白があっても、1つのパスが分かれないようにするため（SC2086）。
  set --
  for _f in $_files; do
    set -- "$@" "$ROOT/$_f"
  done
  must [ "$#" -gt 0 ]
  must [ -z "$(fr920_hits "$@")" ]
}

t_prereq_for_smoke_has_no_port_check() {
  # ポートの確認は、起動と契約の検査の中で、自分の swsc- を止めた後に行う（前提検査には入れない）。
  _body=$(awk '/^swsc_check_(smoke|stop|contract)_prereq\(\)/,/^}/' "$ROOT/scripts/e2e-lib.sh" 2>/dev/null || true)
  must [ -n "$_body" ]
  must [ -z "$(printf '%s\n' "$_body" | grep -E 'socket|8080|4566' || true)" ]
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

t_template_is_valid_json_with_two_containers() {
  must "$jq_bin" -e '
    ([.containerDefinitions[].name] == ["client", "squid"]) and (.networkMode == "awsvpc")
  ' "$ROOT/ecs/task-definition.template.json" >/dev/null
}

t_render_local_sets_upstream_and_mock_destination() {
  render_local "$TMP/local.json" >/dev/null 2>&1
  # shellcheck disable=SC2016 # 単一引用符の中の $sq、$env は jq の変数であり、シェルで展開させない。
  must "$jq_bin" -e '
    ([.containerDefinitions[] | select(.name == "squid")][0]) as $sq
    | ($sq.environment | map({(.name): .value}) | add) as $env
    | ($env.SQUID_UPSTREAM == "mock") and ($env.SQUID_MOCK_HOST == "swsc-wiremock")
      and ($env.SQUID_MOCK_PORT == "8080") and ($sq.image == "swsc-squid:e2e")
  ' "$TMP/local.json" >/dev/null
}

t_render_is_byte_identical_for_same_input() {
  render_local "$TMP/a.json" >/dev/null 2>&1
  render_local "$TMP/b.json" >/dev/null 2>&1
  must cmp "$TMP/a.json" "$TMP/b.json"
}

t_render_fails_on_unknown_placeholder_and_names_it() {
  sed 's/"family": "swsc-e2e"/"family": "{{NOT_DEFINED}}"/' "$ROOT/ecs/task-definition.template.json" >"$TMP/tpl.json"
  _r=0
  render_local "$TMP/out.json" "$TMP/tpl.json" >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must grep -q 'NOT_DEFINED' "$TMP/err"
  must [ ! -e "$TMP/out.json" ]
}

t_render_fails_on_leftover_placeholder_in_key_or_value() {
  sed 's/"memory": "1024"/"memory": "{{lower}}"/' "$ROOT/ecs/task-definition.template.json" >"$TMP/tpl.json"
  _r=0
  render_local "$TMP/out.json" "$TMP/tpl.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
}

t_render_rejects_disallowed_key_by_name() {
  sed 's/"networkMode": "awsvpc",/"networkMode": "awsvpc", "volumes": [],/' "$ROOT/ecs/task-definition.template.json" >"$TMP/tpl.json"
  _r=0
  render_local "$TMP/out.json" "$TMP/tpl.json" >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must grep -q 'volumes' "$TMP/err"
}

t_render_rejects_dependency_condition_other_than_start_or_healthy() {
  sed 's/"condition": "HEALTHY"/"condition": "COMPLETE"/' "$ROOT/ecs/task-definition.template.json" >"$TMP/tpl.json"
  _r=0
  render_local "$TMP/out.json" "$TMP/tpl.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
}

t_render_rejects_health_check_that_is_not_cmd_shell() {
  sed 's/"CMD-SHELL"/"SHELL"/' "$ROOT/ecs/task-definition.template.json" >"$TMP/tpl.json"
  _r=0
  render_local "$TMP/out.json" "$TMP/tpl.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
}

t_render_rejects_malformed_values_without_printing_them() {
  _r=0
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render --template "$ROOT/ecs/task-definition.template.json" \
    --out "$TMP/out.json" --client-image 'a b' --squid-image swsc-squid:e2e \
    --profile local --upstream mock --mock-host h --mock-port 8080 >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  _r=0
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render --template "$ROOT/ecs/task-definition.template.json" \
    --out "$TMP/out.json" --client-image swsc-client:e2e --squid-image swsc-squid:e2e \
    --profile local --upstream 'mock;x' >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  _r=0
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render --template "$ROOT/ecs/task-definition.template.json" \
    --out "$TMP/out.json" --client-image swsc-client:e2e --squid-image swsc-squid:e2e \
    --profile local --upstream mock --mock-host 'a;b' --mock-port 8080 >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  must [ ! -e "$TMP/out.json" ]
}

t_render_fixes_task_level_values_and_omits_roles() {
  render_local "$TMP/out.json" >/dev/null 2>&1
  must "$jq_bin" -e '
    .family == "swsc-e2e" and .networkMode == "awsvpc"
    and .requiresCompatibilities == ["FARGATE"] and .cpu == "512" and .memory == "1024"
    and (has("taskRoleArn") | not) and (has("executionRoleArn") | not)
  ' "$TMP/out.json" >/dev/null
}

t_client_has_proxy_settings_and_no_health_check() {
  render_local "$TMP/out.json" >/dev/null 2>&1
  # shellcheck disable=SC2016 # 単一引用符の中の $c、$env は jq の変数であり、シェルで展開させない。
  must "$jq_bin" -e '
    ([.containerDefinitions[] | select(.name == "client")][0]) as $c
    | ($c.environment | map({(.name): .value}) | add) as $env
    | ($env.HTTP_PROXY == "http://127.0.0.1:3128") and ($env.HTTPS_PROXY == "http://127.0.0.1:3128")
      and ($env.NO_PROXY == "localhost,127.0.0.1") and ($c | has("healthCheck") | not)
  ' "$TMP/out.json" >/dev/null
}

t_template_names_no_mock_default_or_role_arn() {
  # 固定の既定値（mock）と、WireMock の宛先、ロールの ARN を書かない（FR-902、FR-909 の層1）。
  _n=$(grep -cE 'mock|SQUID_MOCK_|arn:' "$ROOT/ecs/task-definition.template.json" || true)
  must [ "$_n" -eq 0 ]
}

t_swsc_render_is_the_only_generation_path() {
  _n=$(grep -hE 'e2e-taskdef\.py.* render|e2e-taskdef\.py render' "$ROOT"/scripts/e2e*.sh | grep -vc '^[[:space:]]*#' || true)
  must [ "$_n" -eq 1 ]
  must grep -q 'swsc_render()' "$ROOT/scripts/e2e-lib.sh"
}

t_swsc_render_matches_direct_render() {
  ( SWSC_ROOT=$ROOT; . "$ROOT/scripts/e2e-lib.sh"; swsc_render "$TMP/via-lib.json" swsc-client:e2e swsc-squid:e2e local mock swsc-wiremock 8080 ) >/dev/null 2>&1
  render_local "$TMP/direct.json" >/dev/null 2>&1
  must cmp "$TMP/via-lib.json" "$TMP/direct.json"
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

t_template_layer1_has_no_mock_default() {
  # 層1: テンプレートに mock の既定値と、WireMock の宛先の環境変数を書かない。
  _n=$(grep -cE 'mock|SQUID_MOCK_' "$ROOT/ecs/task-definition.template.json" || true)
  must [ "$_n" -eq 0 ]
}

t_production_render_with_direct_passes_check() {
  render_production "$TMP/prod.json" direct >/dev/null 2>&1
  must check_production "$TMP/prod.json" >/dev/null 2>&1
}

t_production_render_rejects_upstream_other_than_direct() {
  for _v in mock Mock MOCK ' direct' 'direct ' ''; do
    _r=0
    render_production "$TMP/bad.json" "$_v" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
  done
}

t_production_render_rejects_mock_destination() {
  _r=0
  python3 -B "$ROOT/scripts/e2e-taskdef.py" render --template "$ROOT/ecs/task-definition.template.json" \
    --out "$TMP/bad.json" --client-image swsc-client:prod --squid-image swsc-squid:prod \
    --profile production --upstream direct --mock-host swsc-wiremock --mock-port 8080 \
    >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  must [ ! -e "$TMP/bad.json" ]
}

t_check_production_rejects_each_upstream_variant() {
  render_production "$TMP/prod.json" direct >/dev/null 2>&1
  for _v in mock Mock MOCK ' direct' 'direct ' ''; do
    _lit=$(python3 -B -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$_v")
    mutate "$TMP/prod.json" "$TMP/var.json" "d['containerDefinitions'][1]['environment'][0]['value'] = $_lit"
    _r=0
    check_production "$TMP/var.json" >/dev/null 2>"$TMP/err" || _r=$?
    must [ "$_r" -eq 1 ]
    # 不合格の出力には名前だけを書き、値（mock など）を書かない。
    must [ -z "$(grep -i 'mock' "$TMP/err" || true)" ]
  done
}

t_check_production_rejects_missing_upstream() {
  render_production "$TMP/prod.json" direct >/dev/null 2>&1
  mutate "$TMP/prod.json" "$TMP/var.json" "d['containerDefinitions'][1]['environment'] = []"
  _r=0
  check_production "$TMP/var.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
}

t_check_production_rejects_leftover_mock_destination() {
  render_production "$TMP/prod.json" direct >/dev/null 2>&1
  mutate "$TMP/prod.json" "$TMP/var.json" \
    "d['containerDefinitions'][0]['environment'].append({'name': 'SQUID_MOCK_HOST', 'value': 'h'})"
  _r=0
  check_production "$TMP/var.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  mutate "$TMP/prod.json" "$TMP/var2.json" \
    "d['containerDefinitions'][1]['environment'].append({'name': 'SQUID_MOCK_PORT', 'value': '8080'})"
  _r=0
  check_production "$TMP/var2.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
}

t_check_production_exit_2_when_unreadable() {
  printf '{ broken' >"$TMP/broken.json"
  _r=0
  check_production "$TMP/broken.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 2 ]
  _r=0
  check_production "$TMP/none.json" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 2 ]
}

t_entry_check_production_exit_codes() {
  render_production "$TMP/prod.json" direct >/dev/null 2>&1
  make_base_bin "$TMP/base"
  must rc_is 0 run_e2e "$TMP/base" check-production "$TMP/prod.json"
  must rc_is 2 run_e2e "$TMP/base" check-production
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

t_derive_rejects_unset_upstream() {
  _r=0
  env -i PATH=/usr/bin:/bin sh "$ROOT/ecs/squid/derive-config.sh" "$ROOT/squid-config/squid.conf" "$TMP/d.conf" \
    >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  must [ ! -e "$TMP/d.conf" ]
}

t_derive_rejects_upstream_variants() {
  for _v in MOCK ' mock' 'direct ' Direct ''; do
    _r=0
    derive "$_v" "$TMP/d.conf" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
    must [ ! -e "$TMP/d.conf" ]
  done
}

t_derive_mock_rewrites_only_the_peer_line() {
  derive mock "$TMP/d.conf" >/dev/null 2>&1
  must grep -qxF 'cache_peer swsc-wiremock parent 8080 0 no-query name=wiremock' "$TMP/d.conf"
  must [ "$(grep -cxF 'cache_peer wiremock parent 8080 0 no-query' "$TMP/d.conf" || true)" -eq 0 ]
  must [ "$(grep -cxF 'cache_peer_access wiremock allow api_domains' "$TMP/d.conf")" -eq 1 ]
  must [ "$(grep -cxF 'never_direct allow api_domains' "$TMP/d.conf")" -eq 1 ]
  must [ "$(diff "$ROOT/squid-config/squid.conf" "$TMP/d.conf" | grep -c '^[<>]' || true)" -eq 2 ]
}

t_derive_direct_removes_peer_lines_and_adds_always_direct() {
  derive direct "$TMP/d.conf" >/dev/null 2>&1
  must [ "$(grep -c '^cache_peer' "$TMP/d.conf" || true)" -eq 0 ]
  must [ "$(grep -c '^never_direct' "$TMP/d.conf" || true)" -eq 0 ]
  must [ "$(grep -c 'cache_peer_access' "$TMP/d.conf" || true)" -eq 0 ]
  must [ "$(grep -cxF 'always_direct allow api_domains' "$TMP/d.conf")" -eq 1 ]
}

t_derive_direct_ignores_mock_destination() {
  _r=0
  derive direct "$TMP/d.conf" "" 'a;b' 'x y' >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 0 ]
}

t_derive_mock_rejects_host_injection() {
  # shellcheck disable=SC2016 # for の値は検査の入力値。'x$(id)' はコマンド置換させず文字列のまま渡し、derive が拒否することを確かめるため、展開させない。
  for _h in 'a;b' 'a b' 'x$(id)' 'a/b' '' "$(printf 'a\nb')"; do
    _r=0
    derive mock "$TMP/d.conf" "" "$_h" 8080 >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
    must [ ! -e "$TMP/d.conf" ]
  done
}

t_derive_mock_rejects_bad_port() {
  for _p in '' abc 0 65536 100000 '80 80' -1; do
    _r=0
    derive mock "$TMP/d.conf" "" swsc-wiremock "$_p" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
    must [ ! -e "$TMP/d.conf" ]
  done
}

# 受理側の境界。Why: 5桁（10000〜65535）を弾くバグ（?????* は5文字以上）を、拒否側の値だけでは見逃したため。
t_derive_mock_accepts_port_boundaries() {
  for _p in 1 80 8080 9999 10000 65535; do
    rm -f "$TMP/d.conf"
    _r=0
    derive mock "$TMP/d.conf" "" swsc-wiremock "$_p" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 0 ]
    must grep -q "parent $_p 0 no-query name=wiremock" "$TMP/d.conf"
  done
}

t_derive_rejects_source_without_each_required_line() {
  for _line in 'cache_peer wiremock parent 8080 0 no-query' 'cache_peer_access wiremock allow api_domains' \
    'cache_peer_access wiremock deny all' 'never_direct allow api_domains'; do
    grep -vxF "$_line" "$ROOT/squid-config/squid.conf" >"$TMP/src.conf"
    _r=0
    derive mock "$TMP/d.conf" "$TMP/src.conf" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
    _r=0
    derive direct "$TMP/d.conf" "$TMP/src.conf" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
  done
}

t_derive_rejects_duplicated_required_line() {
  cat "$ROOT/squid-config/squid.conf" >"$TMP/src.conf"
  echo 'cache_peer wiremock parent 8080 0 no-query' >>"$TMP/src.conf"
  _r=0
  derive mock "$TMP/d.conf" "$TMP/src.conf" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
}

t_dockerfile_builds_from_ubuntu_squid_latest() {
  must grep -qx 'FROM ubuntu/squid:latest' "$ROOT/ecs/squid/Dockerfile"
  must grep -qx 'COPY squid.conf /etc/squid/squid.conf.src' "$ROOT/ecs/squid/Dockerfile"
  must grep -qx 'COPY derive-config.sh /usr/local/bin/swsc-derive-config.sh' "$ROOT/ecs/squid/Dockerfile"
  must grep -qx 'ENTRYPOINT \["/usr/local/bin/swsc-entrypoint.sh"\]' "$ROOT/ecs/squid/Dockerfile"
}

t_entrypoint_orders_derive_parse_report_exec() {
  _d=$(grep -n 'swsc-derive-config.sh' "$ROOT/ecs/squid/entrypoint.sh" | head -1 | cut -d: -f1)
  _p=$(grep -n 'squid -k parse' "$ROOT/ecs/squid/entrypoint.sh" | head -1 | cut -d: -f1)
  _u=$(grep -n 'upstream=' "$ROOT/ecs/squid/entrypoint.sh" | head -1 | cut -d: -f1)
  _e=$(grep -n '^exec /usr/local/bin/entrypoint.sh -f /etc/squid/squid.conf -NYC$' "$ROOT/ecs/squid/entrypoint.sh" | head -1 | cut -d: -f1)
  must [ -n "$_d" ] && [ -n "$_p" ] && [ -n "$_u" ] && [ -n "$_e" ]
  must [ "$_d" -lt "$_p" ] && [ "$_p" -lt "$_u" ] && [ "$_u" -lt "$_e" ]
}

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

t_entrypoint_direct_runs_parse_then_hands_over() {
  entry_sandbox "$TMP/ep"
  _out=$(env -i PATH="$TMP/ep/bin:/usr/bin:/bin" SQUID_UPSTREAM=direct sh "$TMP/ep/entry.sh")
  must [ "$_out" = 'swsc-squid: upstream=direct' ]
  must grep -qxF "squid -k parse -f $TMP/ep/out.conf" "$TMP/ep/calls"
  must grep -qxF "entry -f $TMP/ep/out.conf -NYC" "$TMP/ep/calls"
  must grep -qxF 'always_direct allow api_domains' "$TMP/ep/out.conf"
}

t_entrypoint_stops_before_squid_when_upstream_invalid() {
  entry_sandbox "$TMP/ep"
  _r=0
  env -i PATH="$TMP/ep/bin:/usr/bin:/bin" SQUID_UPSTREAM=bogus sh "$TMP/ep/entry.sh" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -ne 0 ]
  must [ ! -e "$TMP/ep/calls" ]
}

t_squid_context_is_a_byte_copy_of_sources() {
  # shellcheck disable=SC2030 # SWSC_ROOT は、このサブシェルの中だけで設定し、e2e-lib.sh と swsc_stage_squid_context が読む値にする。親の SWSC_ROOT は変えない。
  ( SWSC_ROOT=$ROOT; . "$ROOT/scripts/e2e-lib.sh"; swsc_stage_squid_context "$TMP/ctx" ) || return 1
  must cmp "$TMP/ctx/squid.conf" "$ROOT/squid-config/squid.conf"
  must cmp "$TMP/ctx/whitelist.txt" "$ROOT/squid-config/whitelist.txt"
  must cmp "$TMP/ctx/Dockerfile" "$ROOT/ecs/squid/Dockerfile"
  must cmp "$TMP/ctx/derive-config.sh" "$ROOT/ecs/squid/derive-config.sh"
  must cmp "$TMP/ctx/entrypoint.sh" "$ROOT/ecs/squid/entrypoint.sh"
  # shellcheck disable=SC2012 # $TMP/ctx は swsc_stage_squid_context が固定の5ファイル（squid.conf など、英数字と . - のみ）を書き出すディレクトリで、件数の確認に ls を使ってよい。
  must [ "$(ls "$TMP/ctx" | wc -l | tr -d ' ')" -eq 5 ]
}

# 構文の検査（plan 5.1）。Python の検査は、キャッシュを一時置き場へ逃がし、リポジトリに __pycache__ を残さない。
t_shell_syntax_and_python_compile_pass() {
  for _f in scripts/e2e.sh scripts/e2e-lib.sh scripts/e2e-contract.sh scripts/e2e-runner.sh ecs/squid/derive-config.sh ecs/squid/entrypoint.sh tests/m09-execution-and-ci.sh; do
    must sh -n "$ROOT/$_f"
  done
  must env PYTHONPYCACHEPREFIX="$TMP/pyc" python3 -B -m py_compile "$ROOT/scripts/e2e-taskdef.py"
}

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
CONTRACT_FREE='swsc_port_in_use() { echo "port" >>"$SWSC_TEST_SEQ"; return 1; }'
# shellcheck disable=SC2016 # 関数定義の文字列。$SWSC_TEST_SEQ は、contract_go の子の sh で関数を実行するときに展開する。親では展開させない意図。
COLLECT_DEF='swsc_collect() { echo "collect" >>"$SWSC_TEST_SEQ"; }'

t_swsc_aws_refuses_missing_or_non_dummy_credentials() {
  contract_fakes "$TMP/cfake"
  make_base_bin "$TMP/cbase"
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、子の sh が環境変数から展開する。親のシェルでは展開させない意図。 子の sh が SWSC_ROOT から e2e-lib.sh を読む。
  env -i PATH="$TMP/cfake:$TMP/cbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_TEST_DIR="$TMP" SWSC_TEST_SEQ="$TMP/seq.log" \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; swsc_aws ecs list-task-definitions' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、子の sh が環境変数から展開する。親のシェルでは展開させない意図。 子の sh が SWSC_ROOT から e2e-lib.sh を読む。
  env -i PATH="$TMP/cfake:$TMP/cbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_TEST_DIR="$TMP" SWSC_TEST_SEQ="$TMP/seq.log" \
    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=other \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; swsc_aws ecs list-task-definitions' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must [ ! -s "$TMP/rec-aws" ]
}

t_swsc_aws_passes_endpoint_region_and_clears_config_sources() {
  contract_fakes "$TMP/cfake"
  make_base_bin "$TMP/cbase"
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、子の sh が環境変数から展開する。親のシェルでは展開させない意図。 子の sh が SWSC_ROOT から e2e-lib.sh を読む。
  env -i PATH="$TMP/cfake:$TMP/cbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_TEST_DIR="$TMP" SWSC_TEST_SEQ="$TMP/seq.log" \
    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
    sh -c '. "$SWSC_ROOT/scripts/e2e-lib.sh"; swsc_aws ecs list-task-definitions' >/dev/null 2>&1
  _line=$(head -n 1 "$TMP/rec-aws")
  must has_text "$_line" '--endpoint-url http://127.0.0.1:4566'
  must has_text "$_line" '--region ap-northeast-1'
  must has_text "$_line" '--cli-connect-timeout'
  must has_text "$_line" '--cli-read-timeout'
  must grep -qx 'AWS_CONFIG_FILE' "$TMP/rec-aws-env"
  must grep -qx 'AWS_SHARED_CREDENTIALS_FILE' "$TMP/rec-aws-env"
  must grep -qx 'AWS_EC2_METADATA_DISABLED' "$TMP/rec-aws-env"
  if grep -qx 'AWS_PROFILE' "$TMP/rec-aws-env"; then return 1; fi
}

t_port_check_reports_closed_port_as_free() {
  # Why: 関数が無いときも「使用中ではない」と読めてしまうため、先に存在を確かめる。
  ( . "$ROOT/scripts/e2e-lib.sh"; type swsc_port_in_use >/dev/null 2>&1 ) || return 1
  _p=$(python3 -B -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()')
  if ( . "$ROOT/scripts/e2e-lib.sh"; swsc_port_in_use "$_p" ) >/dev/null 2>&1; then return 1; fi
}

t_mask_masks_account_and_arn_and_keeps_hex_hash() {
  # Why: 12桁の実例をファイルに書かず、実行時に作る（ゼロの12桁）。
  _acc=$(printf '%012d' 0)
  _hex=abcdef012345678901234567
  _out=$( . "$ROOT/scripts/e2e-lib.sh"; printf 'id %s acc %s arn:aws:ecs:ap-northeast-1:%s:task/x\n' "$_hex" "$_acc" "$_acc" | swsc_mask )
  must has_text "$_out" "$_hex"
  if has_text "$_out" "$_acc"; then return 1; fi
  if has_text "$_out" 'arn:aws'; then return 1; fi
  must has_text "$_out" '<ACCOUNT_ID>'
  must has_text "$_out" '<RESOURCE_ARN>'
}

t_compare_accepts_reordered_env_and_empty_defaults() {
  contract_base || return 1
  desc_mutate 'C["client"]["portMappings"] = []; C["client"]["healthCheck"] = {}; C["squid"]["dependsOn"] = []' || return 1
  must rc_is 0 compare_cli "$TMP/taskdef.json" "$TMP/describe.json"
  must rc_is 0 compare_cli "$TMP/taskdef.json" "$TMP/describe-bad.json"
}

t_compare_fails_on_image_change() {
  compare_mismatch 'C["squid"]["image"] = "other:1"'
}

t_compare_fails_on_environment_value_and_does_not_print_it() {
  compare_mismatch 'C["squid"]["environment"][0]["value"] = "LEAKCHECK-7731"' 'LEAKCHECK-7731'
}

t_compare_fails_on_essential_change() {
  compare_mismatch 'C["squid"]["essential"] = False'
}

t_compare_fails_on_port_change() {
  compare_mismatch 'C["squid"]["portMappings"][0]["containerPort"] = 3999'
}

t_compare_fails_on_depends_on_change() {
  compare_mismatch 'C["client"]["dependsOn"] = None'
}

t_compare_fails_on_health_check_change() {
  compare_mismatch 'C["squid"]["healthCheck"]["retries"] = 9'
}

t_compare_fails_on_container_count_change() {
  compare_mismatch 'd["containerDefinitions"].pop()'
}

t_compare_fails_on_network_mode_change() {
  compare_mismatch 'd["networkMode"] = "bridge"'
}

t_contract_with_dummy_credentials_removes_old_ministack_first() {
  mkdir -p "$TMP/shim"
  make_base_bin "$TMP/base"
  make_shims "$TMP/shim"
  _r=0
  env -i PATH="$TMP/shim:$TMP/base" HOME="$TMP" SWSC_LOCK_DIR="$UNIT_LOCK" SWSC_E2E_DIR="$TMP/e2e" SWSC_LOG_DIR="$TMP/logs" \
    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
    sh "$ROOT/scripts/e2e.sh" contract >/dev/null 2>"$TMP/err" || _r=$?
  # 前提は通り、最初の docker の呼び出しは、名前の完全一致とラベルで絞った自分の MiniStack の検索である。
  must [ "$_r" -eq 1 ]
  if grep -q '前提不足' "$TMP/err"; then return 1; fi
  must [ "$(head -n 1 "$TMP/rec-docker")" = 'docker ps -aq --filter name=^swsc-ministack$ --filter label=swsc.managed=true' ]
}

t_contract_never_removes_a_same_name_container_without_the_label() {
  contract_setup || return 1
  touch "$TMP/foreign-ministack" "$TMP/docker-run-fail"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '起動'
  # 検索は名前の完全一致とラベルの両方で行い、名前だけの削除は無い。
  must grep -q 'label=swsc.managed=true' "$TMP/rec-docker"
  if grep -q 'docker rm' "$TMP/rec-docker"; then return 1; fi
}

t_contract_success_registers_describes_and_removes_last() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 0 ]
  must seq_before 'docker run' 'list-task-definitions'
  must seq_before 'list-task-definitions' 'register-task-definition'
  must seq_before 'register-task-definition' 'describe-task-definition'
  must seq_before 'describe-task-definition' 'docker inspect'
  must seq_last_is 'docker rm -f fakeid'
  must grep -q '"result": "match"' "$TMP/e2e/ministack-contract.json"
}

t_contract_taskdef_is_the_swsc_render_output() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 0 ]
  must cmp "$TMP/e2e/taskdef.json" "$TMP/taskdef.json"
}

t_contract_run_line_is_localhost_only_socketless_and_pinned() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; contract_main"
  _line=$(grep -F 'docker run' "$TMP/rec-docker" | head -n 1)
  must has_text "$_line" '-p 127.0.0.1:4566:4566'
  must has_text "$_line" '--name swsc-ministack'
  must has_text "$_line" '--label swsc.managed=true'
  must has_text "$_line" 'ministackorg/ministack:1.5.37'
  if has_text "$_line" 'docker.sock'; then return 1; fi
  if has_text "$_line" '--privileged'; then return 1; fi
  if has_text "$_line" 'latest'; then return 1; fi
}

t_contract_port_in_use_stops_before_docker_run() {
  contract_setup || return 1
  contract_go 'swsc_port_in_use() { return 0; }; contract_main'
  must [ "$RC" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '4566'
  if grep -q 'docker run' "$TMP/rec-docker" 2>/dev/null; then return 1; fi
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_removes_old_ministack_before_port_check() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; contract_main"
  must seq_before 'docker rm -f fakeid' 'port'
}

t_contract_stops_when_docker_run_fails_without_aws_calls() {
  contract_setup || return 1
  touch "$TMP/docker-run-fail"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 1 ]
  must [ ! -s "$TMP/rec-aws" ]
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_stops_when_ministack_never_answers() {
  contract_setup || return 1
  touch "$TMP/aws-list-fail"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '起動待ち'
  if grep -q 'register-task-definition' "$TMP/seq.log"; then return 1; fi
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_stops_at_registration_and_names_the_stage() {
  contract_setup || return 1
  touch "$TMP/aws-register-fail"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '登録'
  if grep -q 'describe-task-definition' "$TMP/seq.log"; then return 1; fi
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_mismatch_names_the_stage_and_removes() {
  contract_setup || return 1
  desc_mutate 'C["squid"]["image"] = "other:1"' || return 1
  cp "$TMP/describe-bad.json" "$TMP/describe.json"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '比較'
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_collects_on_failure_before_removal() {
  contract_setup || return 1
  touch "$TMP/aws-register-fail"
  contract_go "$CONTRACT_FREE; $COLLECT_DEF; contract_main"
  must [ "$RC" -eq 1 ]
  # 末尾は、collect、自分の MiniStack の検索（docker ps）、削除（docker rm）の順。
  must [ "$(tail -n 3 "$TMP/seq.log" | head -n 1)" = collect ]
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_failure_without_collect_still_removes() {
  contract_setup || return 1
  touch "$TMP/aws-register-fail"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 1 ]
  if grep -q 'collect' "$TMP/seq.log"; then return 1; fi
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_success_never_collects() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; $COLLECT_DEF; contract_main"
  must [ "$RC" -eq 0 ]
  if grep -q 'collect' "$TMP/seq.log"; then return 1; fi
}

t_contract_interrupt_exits_130_and_removes() {
  contract_setup || return 1
  touch "$TMP/aws-int"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 130 ]
  if grep -q 'register-task-definition' "$TMP/seq.log"; then return 1; fi
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_terminate_exits_143_and_removes() {
  contract_setup || return 1
  touch "$TMP/aws-term"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 143 ]
  must seq_last_is 'docker rm -f fakeid'
}

t_contract_saves_masked_inspect_with_only_localhost_port() {
  contract_setup || return 1
  _acc=$(printf '%012d' 0)
  printf '%s\n' "{\"Mounts\":[],\"Ports\":{\"4566/tcp\":[{\"HostIp\":\"127.0.0.1\",\"HostPort\":\"4566\"}]},\"Arn\":\"arn:aws:ecs:ap-northeast-1:${_acc}:task-definition/swsc-e2e:1\"}" >"$TMP/inspect-out"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 0 ]
  _f="$TMP/e2e/ministack-inspect.json"
  must [ -f "$_f" ]
  if grep -q -F -- "$_acc" "$_f"; then return 1; fi
  if grep -q -F -- 'arn:aws' "$_f"; then return 1; fi
  if grep -q 'docker.sock' "$_f"; then return 1; fi
  must grep -q -F -- '127.0.0.1' "$_f"
  must grep -q -F -- '<RESOURCE_ARN>' "$_f"
}

# 実機（MiniStack 1.5.37）の inspect の形。EXPOSE しただけのポートは null で載る（contract の C4 の実測）。
t_contract_c4_accepts_exposed_but_unpublished_ports() {
  printf '%s\n' '{"Mounts":[{"Type":"volume","Destination":"/etc/localstack/init","Source":"/var/lib/docker/volumes/x/_data"}],"Ports":{"2222/tcp":null,"4566/tcp":[{"HostIp":"127.0.0.1","HostPort":"4566"}]}}' >"$TMP/i.json"
  must contract_c4 "$TMP/i.json"
}

t_contract_c4_rejects_a_second_published_port_a_wider_bind_and_the_socket() {
  printf '%s\n' '{"Mounts":[],"Ports":{"4566/tcp":[{"HostIp":"127.0.0.1","HostPort":"4566"}],"2222/tcp":[{"HostIp":"127.0.0.1","HostPort":"2222"}]}}' >"$TMP/i.json"
  if contract_c4 "$TMP/i.json" >/dev/null 2>&1; then return 1; fi
  printf '%s\n' '{"Mounts":[],"Ports":{"4566/tcp":[{"HostIp":"0.0.0.0","HostPort":"4566"}]}}' >"$TMP/i.json"
  if contract_c4 "$TMP/i.json" >/dev/null 2>&1; then return 1; fi
  printf '%s\n' '{"Mounts":[{"Source":"/var/run/docker.sock","Destination":"/var/run/docker.sock"}],"Ports":{"4566/tcp":[{"HostIp":"127.0.0.1","HostPort":"4566"}]}}' >"$TMP/i.json"
  if contract_c4 "$TMP/i.json" >/dev/null 2>&1; then return 1; fi
  printf '%s\n' '{"Mounts":[],"Ports":{"2222/tcp":null}}' >"$TMP/i.json"
  if contract_c4 "$TMP/i.json" >/dev/null 2>&1; then return 1; fi
}

t_contract_describe_asks_only_the_listed_items() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; contract_main"
  _line=$(grep -F 'describe-task-definition' "$TMP/rec-aws" | head -n 1)
  must has_text "$_line" 'healthCheck'
  must has_text "$_line" 'networkMode'
  must has_text "$_line" 'dependsOn'
  if has_text "$_line" 'taskDefinitionArn'; then return 1; fi
}


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

t_docker_args_writes_args_and_env_for_each_container() {
  runner_setup || return 1
  runner_docker_args "$TMP/taskdef.json" "$TMP/run" || return 1
  must [ -f "$TMP/run/swsc-squid.args" ]
  must [ -f "$TMP/run/swsc-squid.env" ]
  must [ -f "$TMP/run/swsc-client-4242.args" ]
  must [ -f "$TMP/run/swsc-client-4242.env" ]
  must [ -f "$TMP/run/swsc-client-4242.depends" ]
  must grep -qxF 'container:swsc-pause' "$TMP/run/swsc-squid.args"
  must grep -qxF 'container:swsc-pause' "$TMP/run/swsc-client-4242.args"
  must grep -qxF 'swsc-client-4242' "$TMP/run/swsc-client-4242.args"
  must grep -qxF 'HEALTHY swsc-squid' "$TMP/run/swsc-client-4242.depends"
}

t_docker_args_keeps_env_values_out_of_args_and_private_file() {
  runner_setup || return 1
  runner_docker_args "$TMP/taskdef.json" "$TMP/run" || return 1
  must grep -qxF 'HTTP_PROXY=http://127.0.0.1:3128' "$TMP/run/swsc-client-4242.env"
  must [ -z "$(grep -F 'http://127.0.0.1:3128' "$TMP/run/swsc-client-4242.args" || true)" ]
  must [ "$(python3 -B -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$TMP/run/swsc-client-4242.env")" = '0o600' ]
}

# image は docker run のオプションとして読まれない。Why: 先頭が - の image は --privileged などを通してしまう（レビュー M-2）。
t_docker_args_rejects_image_that_starts_with_dash() {
  runner_setup || return 1
  for _img in '--privileged' '-v/:/host' '--network=host'; do
    runner_mutate "d['containerDefinitions'][0]['image'] = '$_img'" || return 1
    _r=0
    runner_docker_args "$TMP/bad.json" "$TMP/run-bad" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -ne 0 ]
    # Why: 変換は全てを検査してから書く。1コンテナでも不正なら、どのファイルも書かれない。
    must [ ! -e "$TMP/run-bad/swsc-squid.args" ]
    must [ ! -e "$TMP/run-bad/swsc-client-4242.args" ]
    rm -rf "$TMP/run-bad"
  done
}

t_docker_args_rejects_newline_in_value() {
  runner_setup || return 1
  runner_mutate "d['containerDefinitions'][0]['environment'][0]['value'] = 'a\\nb'" || return 1
  _r=0
  runner_docker_args "$TMP/bad.json" "$TMP/run" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
}

t_docker_args_writes_nothing_when_a_later_container_has_a_control_character() {
  runner_setup || return 1
  # 後ろのコンテナ（squid）の引数に改行を入れる。前のコンテナ（client）の出力も、残ってはならない。
  runner_mutate "d['containerDefinitions'][1]['command'] = ['a\\nb']" || return 1
  _r=0
  # Why: 実際の呼び出し（swsc_runner_prepare）と同じく、出力先を先に作っておく。無いと書き込み自体が失敗し、検査にならない。
  mkdir -p "$TMP/run-bad"
  runner_docker_args "$TMP/bad.json" "$TMP/run-bad" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  must [ -z "$(ls -A "$TMP/run-bad")" ]
}

# 待機は、コンテナが止まっていれば上限を待たずに止まる。止まっていなければ、従来どおり上限で止まる。
t_runner_wait_wiremock_fails_fast_when_the_container_stopped() {
  runner_setup || return 1
  touch "$TMP/curl-down"
  printf false >"$TMP/running-out"
  _r=0
  runner_run 'swsc_runner_wait_wiremock' >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '停止している'
  rm -f "$TMP/running-out"
  _r=0
  runner_run 'swsc_runner_wait_wiremock' >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '秒以内'
}

t_runner_wait_healthy_fails_fast_when_the_container_stopped() {
  runner_setup || return 1
  printf starting >"$TMP/health-out"
  printf false >"$TMP/running-out"
  _r=0
  runner_run 'swsc_runner_wait_healthy swsc-squid' >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '停止している'
  rm -f "$TMP/running-out"
  _r=0
  runner_run 'swsc_runner_wait_healthy swsc-squid' >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '秒以内'
}

t_runner_probe_squid_fails_fast_when_the_container_stopped() {
  runner_setup || return 1
  touch "$TMP/probe-fail"
  printf false >"$TMP/running-out"
  _r=0
  runner_run 'swsc_runner_probe_squid 4242' >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '停止している'
  rm -f "$TMP/running-out"
  _r=0
  runner_run 'swsc_runner_probe_squid 4242' >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must has_text "$(cat "$TMP/err")" '秒以内'
}

t_docker_args_rejects_items_outside_the_conversion() {
  runner_setup || return 1
  for _stmt in \
    "d['containerDefinitions'][0]['dependsOn'][0]['condition'] = 'COMPLETE'" \
    "d['containerDefinitions'][1]['healthCheck']['command'] = ['CMD', 'kill -0 1']" \
    "d['containerDefinitions'][0]['portMappings'] = [{'containerPort': 3128, 'protocol': 'tcp'}]" \
    "d['networkMode'] = 'bridge'"; do
    runner_mutate "$_stmt" || return 1
    _r=0
    runner_docker_args "$TMP/bad.json" "$TMP/run" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
  done
}

t_docker_args_translates_health_check_to_docker_options() {
  runner_setup || return 1
  runner_docker_args "$TMP/taskdef.json" "$TMP/run" || return 1
  must grep -qxF -- '--health-cmd' "$TMP/run/swsc-squid.args"
  must grep -qxF -- 'kill -0 1' "$TMP/run/swsc-squid.args"
  must [ "$(sed -n '/^--health-interval$/{n;p;}' "$TMP/run/swsc-squid.args")" = 5s ]
  must [ "$(sed -n '/^--health-retries$/{n;p;}' "$TMP/run/swsc-squid.args")" = 5 ]
  must [ "$(sed -n '/^--health-start-period$/{n;p;}' "$TMP/run/swsc-squid.args")" = 10s ]
}

t_docker_args_names_labels_and_forbids_host_privileges() {
  runner_setup || return 1
  runner_docker_args "$TMP/taskdef.json" "$TMP/run" || return 1
  must [ "$(sed -n '/^--name$/{n;p;}' "$TMP/run/swsc-squid.args")" = swsc-squid ]
  must grep -qxF 'swsc.managed=true' "$TMP/run/swsc-squid.args"
  must grep -qxF 'swsc.role=squid' "$TMP/run/swsc-squid.args"
  _bad=$(grep -hE '^(--privileged|-p|--publish|-v|--volume|--mount)$|docker\.sock' "$TMP"/run/*.args || true)
  must [ -z "$_bad" ]
}

t_runner_start_orders_wiremock_admin_check_pause_squid() {
  runner_setup || return 1
  runner_run "swsc_runner_start_all \"$TMP/run\" \"$TMP/taskdef.json\" 4242" >/dev/null 2>&1 || return 1
  _w=$(seq_line 'docker run -d --name swsc-wiremock')
  _c=$(seq_line 'http://127.0.0.1:8080/__admin/mappings')
  _p=$(seq_line 'docker run -d --name swsc-pause')
  _s=$(seq_line 'docker run -d --name swsc-squid')
  must [ -n "$_w" ]
  must [ -n "$_c" ]
  must [ -n "$_p" ]
  must [ -n "$_s" ]
  must [ "$_w" -lt "$_c" ]
  must [ "$_c" -lt "$_p" ]
  must [ "$_p" -lt "$_s" ]
}

t_runner_creates_no_pause_or_squid_when_wiremock_never_ready() {
  runner_setup || return 1
  : >"$TMP/curl-down"
  _r=0
  runner_run "swsc_runner_start_all \"$TMP/run\" \"$TMP/taskdef.json\" 4242" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -ne 0 ]
  must [ -z "$(seq_line 'docker run -d --name swsc-pause')" ]
  must [ -z "$(seq_line 'docker run -d --name swsc-squid')" ]
}

t_runner_waits_for_squid_health_before_probing() {
  runner_setup || return 1
  runner_run "swsc_runner_start_all \"$TMP/run\" \"$TMP/taskdef.json\" 4242" >/dev/null 2>&1 || return 1
  _s=$(seq_line 'docker run -d --name swsc-squid')
  _i=$(seq_line 'docker inspect')
  _p=$(seq_line 'swsc-probe-4242')
  must [ -n "$_i" ]
  must [ -n "$_p" ]
  must [ "$_s" -lt "$_i" ]
  must [ "$_i" -lt "$_p" ]
}

t_runner_every_created_container_has_prefix_and_label() {
  runner_setup || return 1
  runner_run "swsc_runner_start_all \"$TMP/run\" \"$TMP/taskdef.json\" 4242" >/dev/null 2>&1 || return 1
  _noname=$(grep '^docker run ' "$TMP/seq.log" | grep -v -e '--name swsc-' || true)
  must [ -z "$_noname" ]
  _nolabel=$(grep '^docker run ' "$TMP/seq.log" | grep -v -F -- 'swsc.managed=true' || true)
  must [ -z "$_nolabel" ]
  _pub=$(grep -F -- ' -p ' "$TMP/seq.log" | grep -v -F -- '-p 127.0.0.1:8080:8080' || true)
  must [ -z "$_pub" ]
  _forbidden=$(grep -e '--privileged' -e 'docker.sock' "$TMP/seq.log" || true)
  must [ -z "$_forbidden" ]
}

t_runner_client_joins_pause_namespace_and_returns_its_exit_code() {
  runner_setup || return 1
  runner_run "swsc_runner_start_all \"$TMP/run\" \"$TMP/taskdef.json\" 4242" >/dev/null 2>&1 || return 1
  printf '3\n' >"$TMP/client-rc"
  _r=0
  runner_run "swsc_runner_run_client \"$TMP/run\" 4242" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 3 ]
  _c=$(grep -F 'docker run --rm --name swsc-client-4242' "$TMP/seq.log" || true)
  must [ -n "$_c" ]
  case $_c in
    *'--network container:swsc-pause'*) ;;
    *) return 1 ;;
  esac
}

t_runner_remove_managed_removes_only_prefixed_labelled_containers_in_order() {
  runner_setup || return 1
  printf 'a1 swsc-client-4242\nb2 swsc-squid\nc3 swsc-pause\nd4 m05-app\n' >"$TMP/ps-out"
  printf 'e5 swsc-unlabelled\n' >"$TMP/ps-all"
  printf 'swsc-net\nm05-net\n' >"$TMP/net-out"
  runner_run 'swsc_runner_remove_managed' >/dev/null 2>&1 || return 1
  _a=$(seq_line 'docker rm -f a1')
  _b=$(seq_line 'docker rm -f b2')
  _c=$(seq_line 'docker rm -f c3')
  must [ -n "$_a" ]
  must [ -n "$_b" ]
  must [ -n "$_c" ]
  must [ "$_a" -lt "$_b" ]
  must [ "$_b" -lt "$_c" ]
  must [ -z "$(seq_line 'docker rm -f d4')" ]
  must [ -z "$(seq_line 'docker rm -f e5')" ]
  must [ -z "$(seq_line 'docker network rm m05-net')" ]
  _n=$(seq_line 'docker network rm swsc-net')
  must [ -n "$_n" ]
  must [ "$_c" -lt "$_n" ]
  must [ -n "$(seq_line '--filter label=swsc.managed=true')" ]
  must [ -z "$(seq_line 'docker-compose')" ]
}

t_wiremock_total_counts_only_api_urls() {
  runner_setup || return 1
  cat >"$TMP/curl-body" <<'JSON'
{"requests":[{"request":{"url":"/api/users/123"}},{"request":{"url":"/squid-internal-periodic/store_digest"}},{"request":{"url":"/api/orders"}}]}
JSON
  _n=$(runner_run 'swsc_wiremock_total') || return 1
  must [ "$_n" = 2 ]
}

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
CI_FAKES='swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; return "$(cat "$SWSC_TEST_DIR/rc-start" 2>/dev/null || echo 0)"; }
swsc_test_run() { echo test >>"$SWSC_TEST_SEQ"; return "$(cat "$SWSC_TEST_DIR/rc-test" 2>/dev/null || echo 0)"; }
swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; return "$(cat "$SWSC_TEST_DIR/rc-collect" 2>/dev/null || echo 0)"; }
swsc_stop() { echo stop >>"$SWSC_TEST_SEQ"; return 0; }'

# 記録の行を、順に並べた内容で比べる。
seq_is() { # 期待の行（改行区切り）
  [ "$(cat "$TMP/seq.log" 2>/dev/null)" = "$1" ]
}

# 認証情報を一切渡さずに、操作を前提検査の段階で止める（偽の docker が失敗する）。
t_start_prereq_skips_aws_and_credentials() {
  entry_setup || return 1
  touch "$TMP/docker-fail"
  _r=0
  entry_run start >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -ne 0 ]
  if grep -q '前提不足' "$TMP/err"; then return 1; fi
  must [ ! -s "$TMP/rec-aws" ]
}

t_test_and_test_ci_prereq_skip_aws_and_credentials() {
  entry_setup || return 1
  touch "$TMP/docker-fail"
  for _op in test test:ci; do
    _r=0
    entry_run "$_op" >/dev/null 2>"$TMP/err" || _r=$?
    must [ "$_r" -ne 0 ]
    if grep -q '前提不足' "$TMP/err"; then return 1; fi
  done
  must [ ! -s "$TMP/rec-aws" ]
}

# start、test、stop、clean、collect、logs、test:ci は、認証情報が無くても aws を呼ばない。
t_stop_clean_collect_start_test_never_call_aws() {
  entry_setup || return 1
  for _op in start test stop clean collect test:ci; do
    entry_run "$_op" >/dev/null 2>&1 || true
  done
  must [ ! -s "$TMP/rec-aws" ]
}

# 旧基盤のdocker-composeは、どの操作でも呼ばれない（偽の docker-compose が記録する）。
t_all_operations_never_call_docker_compose() {
  entry_setup || return 1
  for _op in start test logs stop clean test:ci collect contract; do
    entry_run "$_op" >/dev/null 2>&1 || true
  done
  must [ -z "$(grep -h 'docker-compose' "$TMP/seq.log" 2>/dev/null || true)" ]
}

# ポートの確認は、自分の swsc- を止めた後に行い、使用中なら何も作らずに止まる。
t_start_checks_port_after_own_stop_and_before_build() {
  entry_setup || return 1
  _r=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数は、lib_call（env -i で起動した子の sh の eval）で展開する。親のシェルでは展開させない意図。
  lib_call 'swsc_port_in_use() { echo port >>"$SWSC_TEST_SEQ"; return 0; }; swsc_start_main' \
    >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must grep -q '旧基盤' "$TMP/err"
  must seq_before 'docker ps' port
  must [ -z "$(seq_line 'docker build')" ]
  must [ -z "$(seq_line 'docker run')" ]
}

# start_main は trap を持たない（test:ci の中で collect より先に stop が走るのを防ぐため）。
t_start_main_has_no_trap() {
  _body=$(awk '/^swsc_start_main\(\)/,/^}/' "$ROOT/scripts/e2e-lib.sh")
  must [ -n "$_body" ]
  must [ -z "$(printf '%s\n' "$_body" | grep -F 'trap' || true)" ]
}

t_stop_is_idempotent_and_removes_only_prefixed_labelled() {
  entry_setup || return 1
  printf 'aaa111 swsc-squid\nbbb222 m05-web\n' >"$TMP/ps-out"
  printf 'swsc-net\nother-net\n' >"$TMP/net-out"
  _r=0
  entry_run stop >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 0 ]
  must grep -q 'docker rm -f aaa111' "$TMP/rec-docker"
  if grep -q 'bbb222' "$TMP/rec-docker"; then return 1; fi
  if grep -q 'other-net' "$TMP/rec-docker"; then return 1; fi
  must grep -q 'docker network rm swsc-net' "$TMP/rec-docker"
  rm -f "$TMP/ps-out" "$TMP/net-out"
  _r=0
  entry_run stop >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 0 ]
}

t_clean_removes_only_own_images_and_dirs() {
  entry_setup || return 1
  # 目印を置いたディレクトリは、swsc が作ったものとして消す。
  mkdir -p "$TMP/e2e" "$TMP/logs"
  : >"$TMP/e2e/.swsc-managed"
  : >"$TMP/logs/.swsc-managed"
  printf 'x\n' >"$TMP/e2e/taskdef.json"
  printf 'x\n' >"$TMP/logs/test.out"
  _r=0
  entry_run clean >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 0 ]
  must [ ! -e "$TMP/e2e" ]
  must [ ! -e "$TMP/logs" ]
  must grep -q 'docker image rm swsc-client:e2e' "$TMP/rec-docker"
  must grep -q 'docker image rm swsc-squid:e2e' "$TMP/rec-docker"
  if grep -E 'docker image rm .*(alpine|wiremock|ministack|ubuntu)' "$TMP/rec-docker" >/dev/null; then return 1; fi
  _r=0
  entry_run clean >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 0 ]
}

# 出力先を利用者のディレクトリへ上書きしても、目印が無ければ消さない（security-review の Low）。
t_clean_refuses_directories_without_the_marker() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e" "$TMP/logs"
  printf 'mine\n' >"$TMP/e2e/important.txt"
  printf 'mine\n' >"$TMP/logs/important.txt"
  _r=0
  entry_run clean >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must [ -f "$TMP/e2e/important.txt" ]
  must [ -f "$TMP/logs/important.txt" ]
  must has_text "$(cat "$TMP/err")" '削除しない'
}

t_clean_still_removes_the_marked_directory_when_the_other_is_refused() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e" "$TMP/logs"
  printf 'mine\n' >"$TMP/e2e/important.txt"
  : >"$TMP/logs/.swsc-managed"
  _r=0
  entry_run clean >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  must [ -f "$TMP/e2e/important.txt" ]
  must [ ! -e "$TMP/logs" ]
}

t_clean_does_not_follow_a_symlink_output_dir() {
  entry_setup || return 1
  mkdir -p "$TMP/target"
  : >"$TMP/target/.swsc-managed"
  printf 'mine\n' >"$TMP/target/important.txt"
  ln -s "$TMP/target" "$TMP/e2e"
  _r=0
  entry_run clean >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
  must [ -f "$TMP/target/important.txt" ]
}

# collect は識別情報を含むファイルを削除する。目印の無い既存ディレクトリでは、何も触れずに失敗する。
t_collect_refuses_a_foreign_log_dir_and_leaves_it_untouched() {
  entry_setup || return 1
  mkdir -p "$TMP/logs"
  printf 'arn:aws:s3:::mine\n' >"$TMP/logs/important.txt"
  _r=0
  entry_run collect >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -ne 0 ]
  must [ "$(cat "$TMP/logs/important.txt")" = 'arn:aws:s3:::mine' ]
  must [ ! -e "$TMP/logs/scrub.txt" ]
  must has_text "$(cat "$TMP/err")" '中身がある'
}

t_collect_marks_a_new_log_dir_and_reuses_it() {
  entry_setup || return 1
  _r=0
  entry_run collect >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 0 ]
  must [ -f "$TMP/logs/.swsc-managed" ]
  _r=0
  entry_run collect >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 0 ]
}

t_prepare_dir_rejects_empty_root_relative_and_symlink() {
  entry_setup || return 1
  mkdir -p "$TMP/real"
  ln -s "$TMP/real" "$TMP/link"
  for _p in '' / relative/path "$TMP/link"; do
    _r=0
    lib_call "swsc_prepare_dir '$_p'" >/dev/null 2>&1 || _r=$?
    must [ "$_r" -eq 1 ]
  done
  must [ ! -e "$TMP/real/.swsc-managed" ]
}

t_prepare_dir_accepts_missing_and_empty_directories() {
  entry_setup || return 1
  mkdir -p "$TMP/empty"
  must lib_call "swsc_prepare_dir '$TMP/new/dir' && swsc_prepare_dir '$TMP/empty'"
  must [ -f "$TMP/new/dir/.swsc-managed" ]
  must [ -f "$TMP/empty/.swsc-managed" ]
}

t_start_refuses_a_foreign_e2e_dir_before_building() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e"
  printf 'mine\n' >"$TMP/e2e/important.txt"
  _r=0
  lib_call 'swsc_port_in_use() { return 1; }; swsc_start_main' >/dev/null 2>"$TMP/err" || _r=$?
  must [ "$_r" -eq 1 ]
  must [ -f "$TMP/e2e/important.txt" ]
  must [ -z "$(seq_line 'docker build')" ]
  must [ -z "$(seq_line 'docker run')" ]
  must has_text "$(cat "$TMP/err")" '中身がある'
}

t_logs_maps_name_to_prefixed_container_and_rejects_unknown() {
  entry_setup || return 1
  _r=0
  entry_run logs bogus >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 2 ]
  entry_run logs squid -f >/dev/null 2>&1 || true
  must grep -q 'docker logs -f swsc-squid' "$TMP/rec-docker"
}

# test:ci の順序: start、test、collect、stop。失敗しても collect が stop より前に届く。
t_test_ci_success_runs_start_test_collect_stop_once() {
  entry_setup || return 1
  _rc=0
  lib_call "$CI_FAKES; swsc_test_ci_main" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must seq_is "$(printf 'start\ntest\ncollect\nstop')"
}

t_test_ci_start_failure_collects_then_stops_and_keeps_rc() {
  entry_setup || return 1
  touch "$TMP/rc-start" && printf 1 >"$TMP/rc-start"
  _rc=0
  lib_call "$CI_FAKES; swsc_test_ci_main" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must seq_is "$(printf 'start\ncollect\nstop')"
}

# collect の最中に TERM を受けても、EXIT の trap が collect と stop をやり直す（_done は stop の後に立てる）。
t_test_ci_signal_during_collect_still_stops() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へシグナルを送るための意図。親の PID にはしない。
  lib_call "$CI_FAKES; "'swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; if [ ! -f "$SWSC_TEST_DIR/sig-sent" ]; then : >"$SWSC_TEST_DIR/sig-sent"; kill -TERM $$; fi; return 0; }; swsc_test_ci_main' \
    >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 143 ]
  must seq_is "$(printf 'start\ntest\ncollect\ncollect\nstop')"
}

t_test_ci_test_failure_keeps_test_rc_and_collects() {
  entry_setup || return 1
  printf 3 >"$TMP/rc-test"
  _rc=0
  lib_call "$CI_FAKES; swsc_test_ci_main" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 3 ]
  must seq_is "$(printf 'start\ntest\ncollect\nstop')"
}

t_test_ci_collect_failure_does_not_change_rc() {
  entry_setup || return 1
  printf 1 >"$TMP/rc-collect"
  _rc=0
  lib_call "$CI_FAKES; swsc_test_ci_main" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must seq_is "$(printf 'start\ntest\ncollect\nstop')"
}

t_test_ci_interrupt_exits_130_and_still_collects_and_stops() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へシグナルを送るための意図。親の PID にはしない。
  lib_call 'swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; kill -INT $$; return 0; }
swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; }
swsc_stop() { echo stop >>"$SWSC_TEST_SEQ"; }
swsc_test_ci_main' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 130 ]
  must seq_is "$(printf 'start\ncollect\nstop')"
}

t_test_ci_terminate_exits_143_and_still_collects_and_stops() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へシグナルを送るための意図。親の PID にはしない。
  lib_call 'swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; kill -TERM $$; return 0; }
swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; }
swsc_stop() { echo stop >>"$SWSC_TEST_SEQ"; }
swsc_test_ci_main' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 143 ]
  must seq_is "$(printf 'start\ncollect\nstop')"
}

# start 操作（単独）: 失敗時は stop だけを呼び、collect は呼ばない。成功時は環境を残す。
t_start_op_failure_stops_without_collect() {
  entry_setup || return 1
  printf 1 >"$TMP/rc-start"
  _rc=0
  lib_call "$CI_FAKES; swsc_start_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must seq_is "$(printf 'start\nstop')"
}

t_start_op_success_keeps_environment() {
  entry_setup || return 1
  _rc=0
  lib_call "$CI_FAKES; swsc_start_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must seq_is 'start'
}

# test 操作: INT と TERM のときだけ stop を呼ぶ。通常の失敗では環境を残す。
t_test_op_failure_keeps_environment() {
  entry_setup || return 1
  _rc=0
  lib_call "$CI_FAKES; swsc_test_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  printf 1 >"$TMP/rc-test"
  rm -f "$TMP/seq.log"
  _rc=0
  lib_call "$CI_FAKES; swsc_test_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must seq_is 'test'
}

t_test_op_interrupt_stops_and_exits_130() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へシグナルを送るための意図。親の PID にはしない。
  lib_call 'swsc_test_run() { echo test >>"$SWSC_TEST_SEQ"; kill -INT $$; return 0; }
swsc_stop() { echo stop >>"$SWSC_TEST_SEQ"; }
swsc_test_op' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 130 ]
  must seq_is "$(printf 'test\nstop')"
}

# test は Squid が稼働していなければ、Client を起動せずに止まる。
t_test_stops_without_client_when_squid_not_running() {
  entry_setup || return 1
  printf false >"$TMP/running-out"
  _rc=0
  entry_run test >/dev/null 2>"$TMP/err" || _rc=$?
  must [ "$_rc" -ne 0 ]
  if grep -q 'swsc-client' "$TMP/seq.log" 2>/dev/null; then return 1; fi
}

# collect: 対象が無くても0。missing.txt に名前を残す。
t_collect_without_containers_exits_0_and_records_missing() {
  entry_setup || return 1
  touch "$TMP/no-containers"
  _rc=0
  entry_run collect >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must grep -q 'swsc-squid' "$TMP/logs/missing.txt"
}

t_collect_gathers_container_logs_squid_logs_and_files() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e"
  printf '{"family":"swsc-e2e"}\n' >"$TMP/e2e/taskdef.json"
  _rc=0
  entry_run collect >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  for _f in containers/swsc-squid.log containers/swsc-wiremock.log containers/swsc-ministack.log \
    squid/access.log squid/cache.log taskdef.json env.txt; do
    must [ -s "$TMP/logs/$_f" ]
  done
  must grep -q 'image=' "$TMP/logs/env.txt"
  # Why: 派生イメージの Id だけでは基底の版を特定できない。基底のダイジェストの行が env.txt に残る（レビュー M-3）。
  must grep -q '^base ubuntu/squid:latest: ' "$TMP/logs/env.txt"
  must grep -q '^base ministackorg/ministack:' "$TMP/logs/env.txt"
}

# 同じ収集を2回すると、同じ構造になる。元が消えた回は、既存の収集物を消さない。
t_collect_is_idempotent_and_keeps_existing_when_source_missing() {
  entry_setup || return 1
  printf 'first run\n' >"$TMP/logs-out"
  entry_run collect >/dev/null 2>&1 || return 1
  touch "$TMP/logs-fail"
  _rc=0
  entry_run collect >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must grep -q 'first run' "$TMP/logs/containers/swsc-squid.log"
  must grep -q 'containers/swsc-squid.log' "$TMP/logs/missing.txt"
}

# 識別情報は、コピーの上でマスクする。ARNと前後が数字でない12桁を消す。
t_collect_masks_arn_and_account_in_copies() {
  entry_setup || return 1
  _acct=$(printf '%s' 1 2 3 4 5 6 7 8 9 0 1 2)
  printf 'role arn:aws:iam::%s:role/x and account %s\n' "$_acct" "$_acct" >"$TMP/logs-out"
  _rc=0
  entry_run collect >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must grep -q '<RESOURCE_ARN>' "$TMP/logs/containers/swsc-squid.log"
  must grep -q '<ACCOUNT_ID>' "$TMP/logs/containers/swsc-squid.log"
  if grep -q "$_acct" "$TMP/logs/containers/swsc-squid.log"; then return 1; fi
  must [ ! -s "$TMP/logs/scrub.txt" ]
}

# UUID の末尾が偶然12桁の数字でも、前が - なので識別情報として扱わない。
t_collect_does_not_treat_uuid_tail_as_account() {
  entry_setup || return 1
  _acct=$(printf '%s' 1 2 3 4 5 6 7 8 9 0 1 2)
  printf 'request 9f1c2d3e-4a5b-6c7d-8e9f-%s\n' "$_acct" >"$TMP/logs-out"
  _rc=0
  entry_run collect >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must grep -q "9f1c2d3e-4a5b-6c7d-8e9f-$_acct" "$TMP/logs/containers/swsc-squid.log"
}

# マスクしても残るファイルは削除し、名前を scrub.txt に記録する。その回は終了コード1。
# 2回目は、元から取り直して識別情報が無いので0（scrub.txt は作り直される）。
t_collect_removes_unmaskable_records_scrub_and_second_run_is_0() {
  entry_setup || return 1
  _acct=$(printf '%s' 1 2 3 4 5 6 7 8 9 0 1 2)
  printf 'arn:aws:iam::%s:role/x\n' "$_acct" >"$TMP/logs-out"
  _rc=0
  lib_call 'swsc_mask() { cat; }; swsc_collect' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must [ ! -e "$TMP/logs/containers/swsc-squid.log" ]
  must grep -q 'containers/swsc-squid.log' "$TMP/logs/scrub.txt"
  _rc=0
  entry_run collect >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must [ ! -s "$TMP/logs/scrub.txt" ]
}

# 一時物の検査: test の出力は一度ファイルへ書き、終了コードを取ってから表示する。
t_test_run_writes_output_to_log_files() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e/run"
  printf 'args\n' >"$TMP/e2e/run/swsc-client-4242.args"
  _rc=0
  entry_run test >"$TMP/out" 2>"$TMP/err" || _rc=$?
  must [ "$_rc" -ne 0 ]
  must [ -f "$TMP/logs/test.out" ]
  must [ -f "$TMP/logs/test.err" ]
}

# 検査の項目1件: 状態（ステータスと受信数）が期待どおりなら PASS、違えば FAIL になる。
t_test_item_compares_status_and_wiremock_count() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e/run"
  printf -- '--name\nswsc-client-4242\n--env-file\n/x/swsc-client-4242.env\nswsc-client:e2e\n' >"$TMP/e2e/run/swsc-client-4242.args"
  printf 'CLIENT_STATUS=200\n' >"$TMP/client-out"
  _rc=0
  lib_call "swsc_test_item 1 名前 http://api.example.com 200 0 $TMP/e2e/run 4242" \
    >"$TMP/out" 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must grep -q '^PASS' "$TMP/out"
  _rc=0
  lib_call "swsc_test_item 1 名前 http://api.example.com 200 1 $TMP/e2e/run 4242" \
    >"$TMP/out" 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must grep -q '^FAIL' "$TMP/out"
}

# Clientへ渡すベースURLが、引数の組み立ての影響を受けず、そのまま docker run に届く。
# Why: set -- が位置パラメータを入れ替えるため、$3 を後から参照すると --label が URL になった（実機で確認）。
t_client_once_passes_base_url_unchanged() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e/run"
  printf -- '--name\nswsc-client-4242\n--label\nswsc.managed=true\n--env-file\n/x/swsc-client-4242.env\nswsc-client:e2e\n' \
    >"$TMP/e2e/run/swsc-client-4242.args"
  lib_call "swsc_client_once $TMP/e2e/run 4242 http://api.example.com" >/dev/null 2>&1 || true
  must grep -q 'TEST_API_BASE_URL=http://api.example.com' "$TMP/rec-docker"
  if grep -q 'TEST_API_BASE_URL=--' "$TMP/rec-docker"; then return 1; fi
}

# WireMock の受信記録は、DELETE /__admin/requests で消す。POST /__admin/requests/reset は 404 になる（実機で確認）。
t_wiremock_reset_uses_delete_requests() {
  entry_setup || return 1
  _rc=0
  lib_call 'swsc_wiremock_reset' >/dev/null 2>&1 || _rc=$?
  must grep -q -e '-X DELETE .*/__admin/requests' "$TMP/rec-curl"
  if grep -q 'requests/reset' "$TMP/rec-curl"; then return 1; fi
}

# ---------------------------------------------------------------------------
# T914: smoke と contract のモード（実通信の検査）の配線と前提。
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------

# smoke の項目が、表（plan 5.2）の1から11の順に登録されている。
t_smoke_registers_items_1_to_11_in_order() {
  _seq=$(grep -E '^  smoke_item [0-9]+ ' "$ROOT/tests/m09-execution-and-ci.sh" | awk '{print $2}' | tr '\n' ' ')
  [ "$_seq" = '1 2 3 4 5 6 7 8 9 10 11 ' ]
}

# contract の項目が、表（plan 5.4）のC1からC6の順に登録されている。
t_contract_registers_c1_to_c6_in_order() {
  _seq=$(grep -E '^  contract_item C[0-9] ' "$ROOT/tests/m09-execution-and-ci.sh" | awk '{print $2}' | tr '\n' ' ')
  [ "$_seq" = 'C1 C2 C3 C4 C5 C6 ' ]
}

# smoke は unit を、Docker を呼ぶ前に実行する。Why: unit が落ちたらDockerを起動しないため（tasks T914）。
t_smoke_runs_unit_before_docker() {
  _f=$ROOT/tests/m09-execution-and-ci.sh
  # shellcheck disable=SC2016 # grep の検索語。検査ファイル内の行をそのまま探すため、$ROOT と引用符を展開させない。
  _u=$(grep -n '^  if ! sh "$ROOT/tests/m09-execution-and-ci.sh" unit' "$_f" | head -n 1 | cut -d: -f1)
  _d=$(grep -n '^  # Why: swsc- の残りを消してから' "$_f" | head -n 1 | cut -d: -f1)
  [ -n "$_u" ] && [ -n "$_d" ] && [ "$_u" -lt "$_d" ]
}

# 認証情報が無い（または test 以外、AWS_PROFILE あり）の contract は、unit も Docker も AWS CLI も呼ばずに止まる。
# Why: 認証情報の検査を最初に行うことで、既定の認証情報へ切り替わる経路を作らないため（FR-905）。
t_contract_precheck_stops_before_unit_docker_aws() {
  _b=$TMP/bin
  make_base_bin "$_b"
  make_shims "$_b"
  _out=$(env -i PATH="$_b" HOME="$TMP" sh "$ROOT/tests/m09-execution-and-ci.sh" contract 2>&1) && return 1
  printf '%s' "$_out" | grep -q '認証情報が無い' || return 1
  no_calls || return 1
  _out=$(env -i PATH="$_b" HOME="$TMP" AWS_ACCESS_KEY_ID=other AWS_SECRET_ACCESS_KEY=test \
    sh "$ROOT/tests/m09-execution-and-ci.sh" contract 2>&1) && return 1
  printf '%s' "$_out" | grep -q '認証情報が無い' || return 1
  no_calls
}

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

t_wf_file_exists() {
  [ -f "$WF" ] || return 1
  # YAML として読めることを yq で確かめる。読めなければ失敗する。
  _y=$(wf_yq_bin) || return 1
  "$_y" -e 'has("jobs")' "$WF" >/dev/null
}

# T2631: shellcheck の設定（.shellcheckrc）と mise の設定（mise.toml）を、必要な行だけに制限する。
# Why: 設定に disable や [tasks]、[hooks]、[env] があると、検査の緩みや任意の実行を、レビューなしに持ち込めるため。
t_shellcheck_config_and_mise_toml_are_restricted() {
  _rc=$ROOT/.shellcheckrc
  _mt=$ROOT/mise.toml
  # .shellcheckrc は4行だけで、disable= を持たない。
  must [ "$(grep -c . "$_rc" || true)" -eq 4 ]
  must [ "$(grep -c 'disable=' "$_rc" || true)" -eq 0 ]
  # mise.toml は min_version と [tools] の6ツールの行だけで、テーブルは [tools] の1つだけ。shellcheck は必ず残す。
  must [ "$(grep -cvE '^(#|$)' "$_mt" || true)" -eq 8 ]
  must grep -qxF 'min_version = "2026.11.3"' "$_mt"
  must [ "$(grep -c '^\[' "$_mt" || true)" -eq 1 ]
  must grep -qxF '[tools]' "$_mt"
  must grep -qxF 'shellcheck = "0.11.0"' "$_mt"
  # [env]、[hooks]、[tasks]、[plugins] は書かない。
  must [ "$(grep -cE '^\[(env|hooks|tasks|plugins)\]' "$_mt" || true)" -eq 0 ]
}

# T2632: mise.toml は min_version と [tools] の6ツール（shellcheck、actionlint、gitleaks、bats、jq、yq）だけを持つ。
# Why: [tasks]、[hooks]、[env]、[plugins] は任意の実行や環境の書き換えを持ち込むため、レビューなしに入れない。
t_mise_toml_is_restricted() {
  _mt=$ROOT/mise.toml
  # 非コメントの行は min_version、[tools]、6ツールの8行だけ。
  must [ "$(grep -cvE '^(#|$)' "$_mt" || true)" -eq 8 ]
  must grep -qxF 'min_version = "2026.11.3"' "$_mt"
  must [ "$(grep -c '^\[' "$_mt" || true)" -eq 1 ]
  must grep -qxF '[tools]' "$_mt"
  must grep -qxF 'shellcheck = "0.11.0"' "$_mt"
  must grep -qxF 'actionlint = "1.7.12"' "$_mt"
  must grep -qxF 'gitleaks = "8.30.1"' "$_mt"
  must grep -qxF 'bats = "1.14.0"' "$_mt"
  must grep -qxF 'jq = "1.8.2"' "$_mt"
  must grep -qxF 'yq = "4.54.2"' "$_mt"
  must [ "$(grep -cE '^(shellcheck|actionlint|gitleaks|bats|jq|yq) = ' "$_mt" || true)" -eq 6 ]
  must [ "$(grep -cE '^\[(env|hooks|tasks|plugins)\]' "$_mt" || true)" -eq 0 ]
}

t_wf_triggers_are_pull_request_and_main_push_only() {
  # pull_request は全ブランチ向けでフィルタ無し。push は main のみ。パスの絞り込みは無い（FR-913）。
  # on は YAML 1.2 として文字列のキーで読まれる。pull_request の値は null（子キーを持たない）。
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '(.on | keys | join(",")) == "pull_request,push" and (.on.pull_request == null) and (.on.push | keys | join(",")) == "branches" and (.on.push.branches | length) == 1 and .on.push.branches[0] == "main"' "$WF" >/dev/null
}

t_wf_permissions_are_contents_read_only() {
  # トップレベルの権限は contents だけで read。job に別の権限を持たせない。
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '(.permissions | keys | join(",")) == "contents" and .permissions.contents == "read" and (.jobs.e2e | has("permissions") | not)' "$WF" >/dev/null
}

t_wf_job_runs_on_ubuntu_2404_with_15_minute_limit() {
  _y=$(wf_yq_bin) || return 1
  # -e で null と false を失敗にする。runs-on と job 全体の timeout-minutes を、値で比べる。
  "$_y" -e '.jobs.e2e."runs-on" == "ubuntu-24.04" and .jobs.e2e."timeout-minutes" == 15' "$WF" >/dev/null
}

t_wf_step_timeouts_are_shellcheck3_actionlint2_gitleaks2_unit3_test_ci10_smoke8_contract5() {
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '(.jobs.e2e.steps[] | select(.name == "shellcheck") | ."timeout-minutes" == 3) and (.jobs.e2e.steps[] | select(.name == "actionlint") | ."timeout-minutes" == 2) and (.jobs.e2e.steps[] | select(.name == "gitleaks") | ."timeout-minutes" == 2) and (.jobs.e2e.steps[] | select(.name == "unit") | ."timeout-minutes" == 3) and (.jobs.e2e.steps[] | select(.name == "test-ci") | ."timeout-minutes" == 10) and (.jobs.e2e.steps[] | select(.name == "smoke") | ."timeout-minutes" == 8) and (.jobs.e2e.steps[] | select(.name == "contract") | ."timeout-minutes" == 5)' "$WF" >/dev/null
}

t_wf_dummy_credentials_are_workflow_env_only() {
  # Why: ダミー値はワークフローの env だけに置く。ステップごとに書くと、どの経路で値が出るかを追えなくなるため。
  # job と各 step に env が無いことも、構造で確かめる。
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '(.env | keys | join(",")) == "AWS_ACCESS_KEY_ID,AWS_SECRET_ACCESS_KEY,AWS_DEFAULT_REGION" and .env.AWS_ACCESS_KEY_ID == "test" and .env.AWS_SECRET_ACCESS_KEY == "test" and .env.AWS_DEFAULT_REGION == "ap-northeast-1" and (.jobs.e2e | has("env") | not) and ([.jobs.e2e.steps[] | select(has("env"))] | length) == 0' "$WF" >/dev/null
}

t_wf_concurrency_groups_pr_by_ref_and_pushes_by_sha() {
  # 式の文字列は環境変数で yq に渡し（strenv）、YAML の値として文字どおり比べる。GitHub Actions の式は展開しない。
  # shellcheck disable=SC2016 # 単一引用符の中の ${{ }} は、GitHub Actions の式として文字どおり比べるための値。
  _g='${{ github.workflow }}-${{ github.event_name == '"'"'pull_request'"'"' && github.ref || github.sha }}'
  # shellcheck disable=SC2016 # 同上。
  _c='${{ github.event_name == '"'"'pull_request'"'"' }}'
  _y=$(wf_yq_bin) || return 1
  WF_CONC_GROUP=$_g WF_CONC_CANCEL=$_c "$_y" -e '(.concurrency | keys | join(",")) == "group,cancel-in-progress" and .concurrency.group == strenv(WF_CONC_GROUP) and .concurrency."cancel-in-progress" == strenv(WF_CONC_CANCEL)' "$WF" >/dev/null
}

t_wf_collect_always_upload_on_failure_stop_always() {
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '(.jobs.e2e.steps[] | select(.name == "collect") | .if == "always()") and (.jobs.e2e.steps[] | select(.name == "stop") | .if == "always()") and (.jobs.e2e.steps[] | select((.uses // "") | test("^actions/upload-artifact@")) | .if == "failure()")' "$WF" >/dev/null
}

t_wf_uploads_logs_with_fixed_name_path_and_seven_day_retention() {
  # upload-artifact の with を、キーの数と値で比べる。name は式を含むため、文字どおりの値として比べる。
  _y=$(wf_yq_bin) || return 1
  # shellcheck disable=SC2016 # yq の式の中の ${{ }} は、ワークフローの値として文字どおり比べる。GitHub Actions の式を展開させない意図。
  # 注意: yq では | と and の結び付きが式の書き方で変わるため、with の中身を括弧で囲んで比べる。
  "$_y" -e '.jobs.e2e.steps[] | select((.uses // "") | test("^actions/upload-artifact@")) | .with | ((length == 4) and .name == "e2e-logs-${{ github.run_id }}-${{ github.run_attempt }}" and .path == "e2e-logs/" and .["retention-days"] == 7 and .["if-no-files-found"] == "warn")' "$WF" >/dev/null
}

t_wf_never_reads_secrets_context() {
  # Why: Secrets を読むと、フォークからの PR に値を渡す経路が生まれるため。
  # 値とキーの全体で secrets の参照を探す。コメントは YAML の値ではないため対象外。
  _y=$(wf_yq_bin) || return 1
  # キー名 secrets（値の中の文字列でなく、マップのキーとして現れるもの）も、どこにも無いことを確かめる。
  "$_y" -e '([.. | select(tag == "!!str") | select(test("secrets[.:]"))] | length) == 0 and (has("secrets") | not) and (.jobs.e2e | has("secrets") | not) and ([.. | select(tag == "!!map") | keys | .[] | select(. == "secrets")] | length) == 0' "$WF" >/dev/null
}

t_wf_run_lines_have_no_expression_or_block_scalar() {
  # Why: run: へ入力や式を展開すると、値がシェルの構文として解釈されるため（インジェクション）。
  # 各 step の run の値を読み、式（${{）、複数行（| や >、改行を含む値）が無いことを確かめる。
  _y=$(wf_yq_bin) || return 1
  # shellcheck disable=SC2016 # yq の式の中の ${{ }} は、run の値に含まれないことを確かめるための文字列。
  "$_y" -e '[.jobs.e2e.steps[] | select(has("run")) | .run | select(contains("\n") or style == "literal" or style == "folded" or contains("${{"))] | length == 0' "$WF" >/dev/null
}

t_wf_expressions_only_in_concurrency_and_artifact_name() {
  # 式（${{）を持つ値は3つだけで、concurrency の group と cancel-in-progress、upload-artifact の name の値であること。
  _y=$(wf_yq_bin) || return 1
  # shellcheck disable=SC2016 # yq の式の中の ${{ }} は、式を持つ値の文字列として比べる。GitHub Actions の式を展開させない意図。
  "$_y" -e '([.. | select(tag == "!!str") | select(contains("${{"))] | length) == 3 and (.concurrency.group | contains("${{")) and (.concurrency."cancel-in-progress" | contains("${{")) and ((.jobs.e2e.steps[] | select((.uses // "") | test("^actions/upload-artifact@")) | .with.name) | contains("${{"))' "$WF" >/dev/null
}

t_wf_uses_checkout_mise_action_and_upload_artifact() {
  _y=$(wf_yq_bin) || return 1
  # uses の並びは action の名前（版の @ より前）で比べる。job 直下に uses は無い。
  "$_y" -e '(.jobs.e2e | has("uses") | not) and ([.jobs.e2e.steps[] | select(has("uses")) | (.uses | sub("@.*$"; ""))] | join(",")) == "actions/checkout,jdx/mise-action,actions/upload-artifact"' "$WF" >/dev/null || return 1
  # Why: タグ（@v7）は付け替えられる。40桁のコミット SHA で固定されていることを確かめる（security-review の Low）。
  "$_y" -e '([.jobs.e2e.steps[] | select(has("uses")) | .uses | select(test("^[^@]+@[0-9a-f]{40}$"))] | length) == 3' "$WF" >/dev/null || return 1
  # 版のコメント（# v7.0.1 など）は YAML の値ではなく構造で読めないため、grep -Eq のまま確かめる。
  grep -qE '^      - uses: actions/checkout@[0-9a-f]{40} # v[0-9]+' "$WF" || return 1
  grep -qE '^      - uses: jdx/mise-action@[0-9a-f]{40} # v[0-9]+' "$WF" || return 1
  grep -qE '^      - uses: actions/upload-artifact@[0-9a-f]{40} # v[0-9]+' "$WF"
}

t_wf_checkout_does_not_persist_credentials() {
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '.jobs.e2e.steps[] | select((.uses // "") | test("^actions/checkout@")) | .with."persist-credentials" == false' "$WF" >/dev/null
}

t_wf_steps_run_in_plan_order() {
  # uses の step は名前の代わりに action の名前（版の @ より前）で数える。
  _y=$(wf_yq_bin) || return 1
  _got=$("$_y" -r '[.jobs.e2e.steps[] | (.name // (.uses | sub("@.*$"; "")))] | join(",")' "$WF") || return 1
  [ "$_got" = "actions/checkout,jdx/mise-action,shellcheck,actionlint,gitleaks,unit,test-ci,smoke,contract,collect,actions/upload-artifact,stop" ]
}

t_wf_each_step_runs_its_command() {
  _y=$(wf_yq_bin) || return 1
  # 静的解析の step は mise which の実体で、自動の導入を止める2つの環境変数を付けて、-s sh -S style で動かす。
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "shellcheck") | .run | (contains("mise which shellcheck") and contains("MISE_EXEC_AUTO_INSTALL=false") and contains("MISE_AUTO_INSTALL=false") and contains("-s sh -S style"))' "$WF" >/dev/null || return 1
  # actionlint の step は、期待する1行と値で完全に比べる（部分一致では、余分な引数や取り違えを見逃すため）。
  # 期待値は .github/workflows/e2e-test.yml の actionlint step の run: の値そのもの。strenv で渡し、式は展開しない。
  # shellcheck disable=SC2016 # 単一引用符の中の $( ) と " は、YAML の run: の値として文字どおり比べるための文字列。
  _al='"$(MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false mise which actionlint)" -shellcheck "$(MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false mise which shellcheck)" .github/workflows/e2e-test.yml'
  WF_RUN_AL=$_al "$_y" -e '.jobs.e2e.steps[] | select(.name == "actionlint") | .run == strenv(WF_RUN_AL)' "$WF" >/dev/null || return 1
  # gitleaks の step は 4.3 節と同じ引数で、実体は mise which で得る。式は含めない。
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "gitleaks") | .run | (contains("mise which gitleaks") and contains("MISE_EXEC_AUTO_INSTALL=false") and contains("MISE_AUTO_INSTALL=false") and contains(" dir . ") and contains("--config .gitleaks.toml") and contains("--redact") and contains("--no-banner") and contains("--exit-code 1"))' "$WF" >/dev/null || return 1
  # mise-action の step は install_args で --locked を渡し、導入を mise.lock に従わせる。
  "$_y" -e '.jobs.e2e.steps[] | select((.uses // "") | test("^jdx/mise-action@")) | .with.install_args == "--locked"' "$WF" >/dev/null || return 1
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "unit") | .run == "sh tests/m09-execution-and-ci.sh unit"' "$WF" >/dev/null || return 1
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "test-ci") | .run == "npm run test:ci && sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000"' "$WF" >/dev/null || return 1
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "smoke") | .run == "sh tests/m09-execution-and-ci.sh smoke"' "$WF" >/dev/null || return 1
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "contract") | .run == "sh tests/m09-execution-and-ci.sh contract"' "$WF" >/dev/null || return 1
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "collect") | .run == "sh scripts/e2e.sh collect"' "$WF" >/dev/null || return 1
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "stop") | .run == "npm run stop"' "$WF" >/dev/null
}

# T2622: M08 の4シナリオは test-ci の検査列に直列で入る。専用の step は増やさない（ステップの順序は変えない）。
t_ci_test_ci_scenarios() {
  _y=$(wf_yq_bin) || return 1
  # 既存の test:ci が先、4シナリオの test:ci が後。失敗したら後は動かない（&&）。
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "test-ci") | .run == "npm run test:ci && sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000"' "$WF" >/dev/null || return 1
  # 専用の step を増やしていないこと。名前付きの step は計画どおり9件（checkout と upload は uses で数えない）。
  "$_y" -e '([.jobs.e2e.steps[] | select(has("name"))] | length) == 9' "$WF" >/dev/null || return 1
  # job 名と required status check の名前（e2e、既存の step 名 smoke と contract）は変わらない。
  "$_y" -e '(.jobs | has("e2e")) and ([.jobs.e2e.steps[] | select(.name == "smoke" or .name == "contract")] | length) == 2' "$WF" >/dev/null
}

t_wf_has_no_docker_compose_call() {
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '([.. | select(tag == "!!str") | select(test("docker[- ]compose"))] | length) == 0' "$WF" >/dev/null
}

t_wf_yaml_parses_with_expected_shape() {
  # YAML として読めることと、形（runner、job 名、job 全体の timeout、権限、トリガー、step 数12）を yq で確かめる。
  # on は文字列のキーとして読まれる（yq は YAML 1.2 で on を真偽値に変えない）。
  _y=$(wf_yq_bin) || return 1
  "$_y" -e '.jobs.e2e."runs-on" == "ubuntu-24.04" and .jobs.e2e."timeout-minutes" == 15 and (.permissions | keys | join(",")) == "contents" and .permissions.contents == "read" and (.on | has("pull_request")) and (.on.push | keys | join(",")) == "branches" and .on.push.branches[0] == "main" and (.jobs.e2e.steps | length) == 12' "$WF" >/dev/null
}

# 壊した定義1件を一時ファイルへ作り、対応する検査が落ちることを確かめる。
wf_broken_case() { # 件名 sedの式 検査の関数
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
t_wf_broken_definitions_fail() {
  _base=${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}
  mkdir -p "$_base" || return 1
  _wf_broken_dir=$(mktemp -d "$_base/wf-broken.XXXXXX") || return 1
  _bad=0
  wf_broken_case permissions 's/^  contents: read$/  contents: write/' t_wf_permissions_are_contents_read_only || _bad=1
  wf_broken_case timeout '/^      - name: unit$/,/timeout-minutes/{s/timeout-minutes: 3/timeout-minutes: 4/}' \
    t_wf_step_timeouts_are_shellcheck3_actionlint2_gitleaks2_unit3_test_ci10_smoke8_contract5 || _bad=1
  wf_broken_case if-always '/^      - name: collect$/,/run:/{/if: always()/d}' \
    t_wf_collect_always_upload_on_failure_stop_always || _bad=1
  wf_broken_case sha-pin 's|actions/checkout@[0-9a-f]\{40\} # v7.0.1|actions/checkout@v4|' \
    t_wf_uses_checkout_mise_action_and_upload_artifact || _bad=1
  # shellcheck disable=SC2016 # sed の式の中の ${{ }} は、ワークフローの文字列として書く。展開させない意図。
  wf_broken_case secrets 's|^        run: sh tests/m09-execution-and-ci.sh smoke$|        run: sh tests/m09-execution-and-ci.sh smoke ${{ secrets.X }}|' \
    t_wf_never_reads_secrets_context || _bad=1
  # 名前の入れ替え（unit と test-ci の名前を互いに置き換える）で、stepの並びを入れ替える。
  wf_broken_case step-order 's/^      - name: unit$/      - name: @@TMP@@/; s/^      - name: test-ci$/      - name: unit/; s/^      - name: @@TMP@@$/      - name: test-ci/' \
    t_wf_steps_run_in_plan_order || _bad=1
  # pull_request を pull_request_target に変えて、トリガーを変える。
  wf_broken_case trigger 's/^  pull_request:$/  pull_request_target:/' t_wf_triggers_are_pull_request_and_main_push_only || _bad=1
  wf_broken_case persist-credentials 's/persist-credentials: false/persist-credentials: true/' \
    t_wf_checkout_does_not_persist_credentials || _bad=1
  # shellcheck disable=SC2016 # sed の式の中の ${{ }} は、ワークフローの文字列として書く。展開させない意図。
  wf_broken_case expression 's|^        run: sh tests/m09-execution-and-ci.sh smoke$|        run: sh tests/m09-execution-and-ci.sh smoke ${{ github.x }}|' \
    t_wf_run_lines_have_no_expression_or_block_scalar || _bad=1
  wf_broken_case retention 's/retention-days: 7/retention-days: 30/' \
    t_wf_uploads_logs_with_fixed_name_path_and_seven_day_retention || _bad=1
  # 作ったファイルを1つずつ消してから、空の場所を消す（rm -rf は使わない）。
  for _f in "$_wf_broken_dir"/*.yml; do
    if [ -e "$_f" ]; then rm -f "$_f" || _bad=1; fi
  done
  rmdir "$_wf_broken_dir" || _bad=1
  [ "$_bad" -eq 0 ]
}

# T2634: actionlint は式の誤りで失敗し、現在のワークフローでは成功する（永続する回帰検査）。
# Why: actionlint が式を読めなくなると、CI の静的検査が何も止めないまま通るため。
t_actionlint_rejects_expression_error() {
  # mise は、いまのディレクトリの mise.toml で版を決めるため、リポジトリの根で呼ぶ。
  _al=$(cd "$ROOT" && MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise which actionlint 2>/dev/null) || return 1
  [ -n "$_al" ] || return 1
  _base=${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}
  mkdir -p "$_base" || return 1
  _d=$(mktemp -d "$_base/actionlint-expr.XXXXXX") || return 1
  _bad_wf=$_d/expr-error.yml
  # shellcheck disable=SC2016 # 単一引用符の here-document の中の ${{ }} は、式の文字列として書く。展開させない意図。
  cat >"$_bad_wf" <<'EOF'
on: push
jobs:
  e2e:
    runs-on: ubuntu-24.04
    steps:
      - run: echo ${{ does.not.exist }}
EOF
  "$_al" "$_bad_wf" >/dev/null 2>&1
  _bad_rc=$?
  # shellcheck disable=SC2031 # ここの WF は親のシェルの値（リポジトリのワークフロー）。部分シェルの変更は及ばない。
  "$_al" "$WF" >/dev/null 2>&1
  _ok_rc=$?
  # 一時のワークフローを1つずつ消してから、空の場所を消す。
  rm -f "$_bad_wf" || return 1
  rmdir "$_d" || return 1
  [ "$_bad_rc" -ne 0 ] && [ "$_ok_rc" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T916 文書（docs/ローカル実行とCI.md、README.md、AGENTS.md）
# Why: 文書は利用者とCIの入口になるため、節、リンク、識別情報の不在、既存の行の保持を固定する。
# ---------------------------------------------------------------------------
t_doc_file_exists() {
  [ -f "$ROOT/docs/ローカル実行とCI.md" ]
}

t_doc_has_one_h1_first() {
  _doc="$ROOT/docs/ローカル実行とCI.md"
  head -n 1 "$_doc" | grep -q '^# ' || return 1
  [ "$(grep -c '^# ' "$_doc")" -eq 1 ]
}

t_doc_has_required_sections() {
  _doc="$ROOT/docs/ローカル実行とCI.md"
  for _h in 実行方法 ダミー認証情報の設定 検査の層と実行主体 構成 旧基盤との関係 CIの見方 \
    所要時間の目安 再現性 本番向けの検査 ゲートの結果; do
    grep -Fxq -- "## $_h" "$_doc" || return 1
  done
}

t_doc_names_layers_executors_and_gate_scope() {
  _doc="$ROOT/docs/ローカル実行とCI.md"
  for _w in unit smoke contract エージェント CI 利用者の端末; do
    grep -Fq -- "$_w" "$_doc" || return 1
  done
  grep -Fq '品質ゲート' "$_doc" && grep -Fq '登録しない' "$_doc"
}

t_doc_dummy_credentials_names_only() {
  _doc="$ROOT/docs/ローカル実行とCI.md"
  grep -Fq 'AWS_ACCESS_KEY_ID' "$_doc" || return 1
  grep -Fq 'AWS_SECRET_ACCESS_KEY' "$_doc" || return 1
  # Why: 変数に値を代入する行があると、ダミーでも値を文書へ書いたことになる（MiniStack の値も書かない）。
  ! grep -Eq 'AWS_[A-Z_]+[[:space:]]*=' "$_doc" || return 1
  grep -Fq '自分のターミナル' "$_doc" || return 1
  grep -Fq 'リポジトリに' "$_doc" || return 1
  grep -Fq '公式の MiniStack の案内に従う' "$_doc" || return 1
  grep -Fq '要らない' "$_doc"
}

t_doc_startup_order_is_wiremock_pause_squid() {
  _line=$(grep -F '起動順' "$ROOT/docs/ローカル実行とCI.md" | head -n 1)
  case $_line in
    *WireMock*管理API*pause*Squid*) return 0 ;;
  esac
  return 1
}

t_doc_counts_api_urls_only() {
  _doc="$ROOT/docs/ローカル実行とCI.md"
  grep -Fq '/api/' "$_doc" || return 1
  grep -Fq '受信数' "$_doc"
}

t_doc_stop_uses_rm_f_and_states_sigterm() {
  _doc="$ROOT/docs/ローカル実行とCI.md"
  grep -Fq 'docker rm -f' "$_doc" || return 1
  grep -Fq 'SIGTERM' "$_doc"
}

t_doc_duration_defers_to_ci() {
  # S26 T2626: 初回CIの実測値と、上限の根拠を書く。
  _sec=$(sed -n '/^## 所要時間の目安$/,/^## 再現性/p' "$ROOT/docs/ローカル実行とCI.md")
  printf '%s\n' "$_sec" | grep -Fq 'CI の初回実行で実測した' || return 1
  for _s in unit test-ci smoke contract; do
    printf '%s\n' "$_sec" | grep -q "^| \`$_s\` |.*秒 |.*分 |" || return 1
  done
  printf '%s\n' "$_sec" | grep -Fq '上限の根拠'
}

t_doc_gate_summary_covers_g1_to_g5() {
  _sec=$(sed -n '/^## ゲートの結果$/,$p' "$ROOT/docs/ローカル実行とCI.md")
  for _g in G1 G2 G3 G4 G5; do
    printf '%s\n' "$_sec" | grep -Fq "$_g" || return 1
  done
}

t_doc_readme_links_and_lists_npm_run() {
  _readme="$ROOT/README.md"
  grep -Fq '(docs/ローカル実行とCI.md)' "$_readme" || return 1
  for _op in start test logs stop clean test:ci; do
    grep -Fq "npm run $_op" "$_readme" || return 1
  done
}

# S26 T2630: Compose の削除とともに、README の旧 Compose 手順も削除した。現行の手順だけを載せる。
t_doc_readme_has_no_old_compose_procedure() {
  _readme="$ROOT/README.md"
  ! grep -Fq 'docker-compose' "$_readme" || return 1
  ! grep -Fq '旧 Compose 手順' "$_readme" || return 1
  [ ! -e "$ROOT/docker-compose.yml" ]
}

t_doc_agents_row_registers_unit_smoke_not_contract() {
  _row=$(grep -F 'tests/m09-execution-and-ci.sh' "$ROOT/AGENTS.md" | grep '^| ' | head -n 1)
  [ -n "$_row" ] || return 1
  case $_row in
    *unit*smoke*contract*登録しない*) return 0 ;;
  esac
  return 1
}

t_doc_keeps_lines_checked_by_m07_m08_s14() {
  _readme="$ROOT/README.md"
  grep -Fq '(docs/シナリオ隔離.md)' "$_readme" || return 1
  grep -Fq '(docs/E2Eテスト.md)' "$_readme" || return 1
  grep -Fq '(docs/ポート公開範囲.md)' "$_readme" || return 1
  # S26: Squid はホストへ公開しない。README は pause の namespace の中で待ち受けると書く。
  grep -Fxq -- '- pause コンテナと共有する namespace の中で 127.0.0.1:3128 をリッスン（ホストへは公開しない）' "$_readme" || return 1
  grep -Fxq -- '- REST API mock server（127.0.0.1:8080）' "$_readme"
}

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
t_gate_runs_shellcheck_with_pinned_options() {
  # ゲートは shellcheck を共通の関数（resolve_tool）で照合する。版の照合の本体は関数のファイルにある。
  gate_sources | grep -Fq 'resolve_tool shellcheck' || return 1
  _which=$(cat "$ROOT/scripts/lib/resolve-tool.sh" | grep -F 'mise which' || true)
  must [ -n "$_which" ]
  printf '%s\n' "$_which" | grep -Fq 'MISE_EXEC_AUTO_INSTALL=false' || return 1
  printf '%s\n' "$_which" | grep -Fq 'MISE_AUTO_INSTALL=false' || return 1
  printf '%s\n' "$_which" | grep -Fq 'MISE_LOCKED=1' || return 1
  gate_sources | grep -Fq -- '--version' || return 1
  gate_sources | grep -Fq -- '-s sh -S style' || return 1
  # mise current も、同じ3つの環境変数で自動導入を止めて呼ぶ。
  _cur=$(cat "$ROOT/scripts/lib/resolve-tool.sh" | grep -F 'mise current' || true)
  must [ -n "$_cur" ]
  printf '%s\n' "$_cur" | grep -Fq 'MISE_EXEC_AUTO_INSTALL=false' || return 1
  printf '%s\n' "$_cur" | grep -Fq 'MISE_AUTO_INSTALL=false' || return 1
  printf '%s\n' "$_cur" | grep -Fq 'MISE_LOCKED=1' || return 1
  # 自動導入の停止と版の不一致の各ガードは、FAILED: の文言を持つ。
  [ "$(gate_sources | grep -c 'FAILED:' || true)" -ge 2 ] || return 1
  # 検査対象は、ファイルの一覧を NUL 区切りで xargs に渡す。
  # shellcheck disable=SC2016 # 単一引用符の中の $actual_path は、検査対象のファイルの文字列として一致させる。展開させない意図。
  gate_sources | grep -Fq -- 'xargs -0 "$actual_path"' || return 1
  # sh -n の loop は shellcheck に置き換えたため残さない。mise exec は使わない。
  [ "$(gate_sources | grep -cF 'sh -n' || true)" -eq 0 ] || return 1
  [ "$(gate_sources | grep -cF 'mise exec' || true)" -eq 0 ]
}

# T2633: 品質ゲートは actionlint と yq の実体を mise which で得て、自動の導入を止める3つの環境変数を各行に付ける。
# Why: 版の固定を、PATH や mise exec の自動導入に任せると、ゲートの結果が環境で変わるため。
t_gate_runs_pinned_tools() {
  # 共通の関数（resolve_tool）を、ゲートが actionlint と yq について呼ぶ（plan 4.2 節）。
  # コメントを除き、行頭の呼び出しとして探す（コメントや文字列の中の一致で通さない）。
  gate_sources | grep -vE '^[[:space:]]*#' | grep -Fq 'resolve_tool actionlint ' || return 1
  gate_sources | grep -vE '^[[:space:]]*#' | grep -Fq 'resolve_tool yq ' || return 1
  gate_sources | grep -vE '^[[:space:]]*#' | grep -Fq 'resolve_tool gitleaks ' || return 1
  # mise which と mise current を呼ぶ行は、共通の関数のファイルにある。コメントを除き、3つの環境変数を必ず付ける。
  _calls=$(cat "$ROOT/scripts/lib/resolve-tool.sh" | grep -E 'mise (which|current) ' | grep -vE '^[[:space:]]*#' || true)
  must [ -n "$_calls" ]
  printf '%s\n' "$_calls" | grep -Fv 'MISE_EXEC_AUTO_INSTALL=false' | grep -q . && return 1
  printf '%s\n' "$_calls" | grep -Fv 'MISE_AUTO_INSTALL=false' | grep -q . && return 1
  printf '%s\n' "$_calls" | grep -Fv 'MISE_LOCKED=1' | grep -q . && return 1
  # mise exec と || true は、コメントを除いて書かない。
  [ "$(gate_sources | grep -vE '^[[:space:]]*#' | grep -cF 'mise exec' || true)" -eq 0 ] || return 1
  [ "$(gate_sources | grep -vE '^[[:space:]]*#' | grep -cF '|| true' || true)" -eq 0 ]
}

# T-R0254: 品質ゲートは、JSON を扱う検査より前に、jq の実体と版を確かめる。
# Why: jq を先頭で照合しないと、未導入や版違いが後段の JSON の検査の途中で、分かりにくい失敗として現れるため。
t_gate_checks_jq_first() {
  _gf=$ROOT/scripts/quality-gate.sh
  _jq=$(grep -n '^if ! resolve_tool jq ' "$_gf" | head -1 | cut -d: -f1)
  _yq=$(grep -n '^if ! resolve_tool yq ' "$_gf" | head -1 | cut -d: -f1)
  [ -n "$_jq" ] || return 1
  [ -n "$_yq" ] || return 1
  [ "$_jq" -lt "$_yq" ] || return 1
  sed -n "${_jq}p" "$_gf" | grep -Fq "resolve_tool jq 's/^jq-//p' --version" || return 1
  return 0
}

# swsc_count_api_requests（jq）は、接頭辞 /api/ の URL だけを数える。固定の入力で件数を確かめる。
t_count_api_requests_counts_only_api_urls() {
  printf '%s' '{"requests":[{"request":{"url":"/api/a"}},{"request":{"url":"/squid-internal-periodic/x"}},{"request":{"url":"/api/b"}}]}' \
    > "$TMP/requests.json"
  SWSC_ROOT=$ROOT
  _n=$(. "$ROOT/scripts/e2e-lib.sh"; swsc_count_api_requests < "$TMP/requests.json") || return 1
  must [ "$_n" = 2 ]
}

# T-R0253: JSON の値の取り出しは jq に置き換える（plan 9.2 節）。Python の json.load を残してよいのは、
# JSON を書き換える mutate() の中だけである。取り出しではなく、壊した入力や変更後の JSON を作るための経路だから。
# Why: m03 と m07 の取り出しを、jq へ移したことを、json.load の不在で確かめる。
t_json_extraction_uses_jq() {
  for _f in m03-wiremock-scenarios.sh m07-scenario-isolation.sh; do
    [ "$(grep -c 'json\.load(' "$ROOT/tests/$_f" || true)" -eq 0 ] || return 1
  done
  # m09 は、JSON を書き換えて写しを作る関数と、Docker の出力を複数の条件で確かめる関数を除き、JSON の読み込みを残さない。
  # Why: これらは取り出しではなく、壊した入力や変更後の写しを作る経路（mutate と同じ役割）である。
  #      contract_c4 は複数の条件と個別の失敗文言を持つため、値の取り出しの置き換えの対象外とする。
  _outside=$(awk '/^(mutate|desc_mutate|runner_mutate|contract_base|contract_c4|contract_c6)\(\) \{/ { inm = 1 } inm && /^}/ { inm = 0; next } !inm' \
    "$ROOT/tests/m09-execution-and-ci.sh" | grep -c 'json\.load(' || true)
  [ "$_outside" -eq 0 ] || return 1
  # scripts の e2e-contract.sh は JSON を読まない。e2e-lib.sh は、詳細な判定の swsc_wiremock_count_path だけが読む。
  [ "$(grep -c 'json\.load(' "$ROOT/scripts/e2e-contract.sh" || true)" -eq 0 ] || return 1
  _lib=$(awk '/^swsc_wiremock_count_path\(\) \{/ { inm = 1 } inm && /^}/ { inm = 0; next } !inm' \
    "$ROOT/scripts/e2e-lib.sh" | grep -c 'json\.load(' || true)
  [ "$_lib" -eq 0 ]
}

# T-R0235: .gitleaks.toml は独自の規則だけを持ち、既定の規則の読み込み（useDefault）、
# トップレベルの [allowlist]、stopwords を書かない。コメントの中の語は対象外。
# Why: 既定の規則や全体の除外は、置き換え前の検査の範囲を黙って狭めるため（clarify.md 7章）。
t_gitleaks_config_has_no_global_allowlist() {
  _cfg=$ROOT/.gitleaks.toml
  [ -f "$_cfg" ] || return 1
  _code=$(sed '/^[[:space:]]*#/d' "$_cfg") || return 1
  printf '%s\n' "$_code" | grep -q 'useDefault' && return 1
  printf '%s\n' "$_code" | grep -qE '^[[:space:]]*\[allowlist\][[:space:]]*$' && return 1
  printf '%s\n' "$_code" | grep -q 'stopwords' && return 1
  # 作業ツリーの .gitleaksignore は、リポジトリ直下に置かない（cd の後で確かめる）。
  ( cd "$ROOT" && [ ! -e .gitleaksignore ] ) || return 1
  # 追跡対象と作業ツリーのスクリプト・テスト・ワークフロー・設定に、除外の印が無いこと。
  # 印の文字列は組み立てて持つ。この検査のファイル自身に一致させないため。文書は対象外。
  _tok=$(printf '%s:%s' 'gitleaks' 'allow')
  _hits=$(cd "$ROOT" && git grep -l -F "$_tok" -- scripts tests .github .gitleaks.toml) ; _rc=$?
  [ "$_rc" -eq 1 ] || return 1
  return 0
}

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
t_gitleaks_rules_detect_runtime_built_values() {
  _gl=$(cd "$ROOT" && MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise which gitleaks 2>/dev/null) || return 1
  [ -x "$_gl" ] || return 1
  _cfg=$ROOT/.gitleaks.toml
  _base=${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}
  mkdir -p "$_base" || return 1
  _d=$(mktemp -d "$_base/gitleaks-rules.XXXXXX") || return 1
  _bad=0
  # ここから先は、途中で失敗しても作業ディレクトリを gl_cleanup で消す（return で抜けない）。
  # 実行時に組み立てた値。実在しない形の値だけを使う。
  _v12=$(printf '%s%s%s' '1234' '5678' '9012')
  _arn=$(printf '%s:%s:%s::%s:role/%s' 'arn' 'aws' 'iam' "$_v12" 'TestRole')
  _key=$(printf '%s%s%s' 'AK' 'IA' 'ABCDEFGHIJKLMNOP')
  for _k in num arn key clean; do mkdir -p "$_d/$_k" || _bad=1; done
  # 段2のアカウントIDの規則は、account や aws などの語が近くにある12桁を検出する（8.1節）。語を添える。
  printf '%s %s\n' 'account' "$_v12" >"$_d/num/value.txt" || _bad=1
  printf '%s\n' "$_arn" >"$_d/arn/value.txt" || _bad=1
  printf '%s\n' "$_key" >"$_d/key/value.txt" || _bad=1
  printf '%s\n' 'the quick brown fox, review notes only' >"$_d/clean/value.txt" || _bad=1
  gl_expect_detect "$_gl" "$_cfg" "$_d/num" "$_d/num.out" "$_v12" || _bad=1
  gl_expect_detect "$_gl" "$_cfg" "$_d/arn" "$_d/arn.out" "$_arn" || _bad=1
  gl_expect_detect "$_gl" "$_cfg" "$_d/key" "$_d/key.out" "$_key" || _bad=1
  gl_expect_clean "$_gl" "$_cfg" "$_d/clean" "$_d/clean.out" || _bad=1
  gl_cleanup "$_d" || _bad=1
  [ "$_bad" -eq 0 ]
}

# T-R0348: 段1の path 規則が、FR-R0210 の11ファイルに12桁の番号を検出し、対象外のパスには検出しないことを確かめる。
# Why: path 規則の範囲が狭まると、置き換え前の検査の範囲を黙って失うため（FR-R0210）。
# gitleaks は絶対パスで File を書くため、一時ディレクトリの中へ移り、相対パスで走査する。
# 値は printf で組み立て、ファイルに固定で書かない（NFR-R0206）。検出の出力は JSON で読み、値を表示しない。
t_gitleaks_path_rules_cover_eleven_files() {
  _gl=$(cd "$ROOT" && MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise which gitleaks 2>/dev/null) || return 1
  [ -x "$_gl" ] || return 1
  _jq=$(cd "$ROOT" && MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise which jq 2>/dev/null) || return 1
  [ -x "$_jq" ] || return 1
  _cfg=$ROOT/.gitleaks.toml
  _base=${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}
  mkdir -p "$_base" || return 1
  _d=$(mktemp -d "$_base/gitleaks-path.XXXXXX") || return 1
  # 報告は作業ディレクトリの中に置く。gitleaks は走査の後に報告を書くため、報告自身は走査されない。
  _json=$_d/r.json
  _v=$(printf '%s%s%s' '1234' '5678' '9012')
  _bad=0
  _targets='docs/ローカル実行とCI.md README.md AGENTS.md docs/ポート公開範囲.md squid-config/squid.conf squid-config/whitelist.txt ecs/task-definition.template.json ecs/squid/Dockerfile ecs/squid/derive-config.sh ecs/squid/entrypoint.sh docs/E2Eテスト.md'
  _other='other/a.txt'
  for _rel in $_targets $_other; do
    mkdir -p "$_d/$(dirname "$_rel")" || _bad=1
    printf '%s\n' "$_v" >"$_d/$_rel" || _bad=1
  done
  ( cd "$_d" && "$_gl" dir . --config "$_cfg" --redact --no-banner --exit-code 0 --report-format json --report-path "$_json" ) >/dev/null 2>&1 || _bad=1
  _hits=$("$_jq" -r '.[]? | .RuleID + " " + .File' "$_json") || _bad=1
  for _rel in $_targets; do
    if printf '%s\n' "$_hits" | grep -qxF "identity-doc-12digit $_rel"; then :; else _bad=1; fi
  done
  if printf '%s\n' "$_hits" | grep -qF " $_other"; then _bad=1; fi
  gl_cleanup "$_d" || _bad=1
  [ "$_bad" -eq 0 ]
}

# 段1の3規則（identity-doc の id を持つ規則）の path は、3つとも同じ文字列であることを確かめる。
# Why: 3規則の path がずれると、一部の規則だけ対象のファイルが狭まり、検出の範囲を黙って失うため。
t_gitleaks_stage1_paths_are_identical() {
  _cfg=$ROOT/.gitleaks.toml
  [ -f "$_cfg" ] || return 1
  _paths=$(awk '/^\[\[rules\]\]/ { on = 0 } /^id = "identity-doc-/ { on = 1 } on && /^path = / { print }' "$_cfg") || return 1
  [ "$(printf '%s\n' "$_paths" | grep -c '^path = ' || true)" -eq 3 ] || return 1
  [ "$(printf '%s\n' "$_paths" | sort -u | grep -c . || true)" -eq 1 ]
}

t_gate_m09_block_exists_and_is_closed() {
  _blk=$(gate_m09_block) || return 1
  gate_has "$_blk" 'run sh tests/m09-execution-and-ci.sh unit' || return 1
  printf '%s\n' "$_blk" | tail -n 1 | grep -Fxq 'fi'
}

t_gate_m09_block_registers_unit_then_smoke_as_separate_runs() {
  _blk=$(gate_m09_block) || return 1
  _u=$(printf '%s\n' "$_blk" | grep -n '^  run sh tests/m09-execution-and-ci.sh unit$' | cut -d: -f1)
  _s=$(printf '%s\n' "$_blk" | grep -n '^  run sh tests/m09-execution-and-ci.sh smoke$' | cut -d: -f1)
  must [ -n "$_u" ]
  must [ -n "$_s" ]
  must [ "$_u" -lt "$_s" ]
}

t_gate_m09_block_condition_covers_targets_and_squid_inputs() {
  _blk=$(gate_m09_block) || return 1
  _cond=$(printf '%s\n' "$_blk" | head -n 1)
  for _t in 'scripts/e2e' 'ecs/' 'tests/m09-execution-and-ci\.sh' 'e2e-test\.yml' 'docs/ローカル実行とCI\.md' \
    'package\.json' '\.gitignore' 'squid-config/' 'test-client/' 'wiremock-scenarios/' 'Dockerfile'; do
    must gate_has "$_cond" "$_t"
  done
}

t_gate_m09_block_placed_after_integration_check_and_before_summary() {
  _gf=$ROOT/scripts/quality-gate.sh
  _m08=$(grep -n "managed_check '統合テストの後" "$_gf" | cut -d: -f1)
  _gif=$(grep -n "^if has_match '.*scripts/e2e" "$_gf" | cut -d: -f1)
  # shellcheck disable=SC2016 # grep の正規表現として \$status を文字どおり一致させる。品質ゲートの行の $status を探す意図。
  _sum=$(grep -n '^if \[ "\$status" -eq 0 \]' "$_gf" | cut -d: -f1)
  must [ -n "$_m08" ]
  must [ -n "$_gif" ]
  must [ -n "$_sum" ]
  must [ "$_gif" -gt "$_m08" ]
  must [ "$_gif" -lt "$_sum" ]
}

t_gate_m09_block_checks_leftover_containers_after_smoke() {
  _blk=$(gate_m09_block) || return 1
  must gate_has "$_blk" "managed_check 'M09 のコンテナ（swsc-）が残っている、または確かめられない'"
  _s=$(printf '%s\n' "$_blk" | grep -n '^  run sh tests/m09-execution-and-ci.sh smoke$' | cut -d: -f1)
  _d=$(printf '%s\n' "$_blk" | grep -n 'managed_check' | cut -d: -f1)
  must [ -n "$_s" ]
  must [ -n "$_d" ]
  must [ "$_s" -lt "$_d" ]
}

# T2621: Compose の項目を外し、管理対象の残存検査（swsc_check_managed_empty）へ置き換えた品質ゲートの検査。
t_gate_no_compose_calls_or_or_true_wrapped_docker() {
  _gf=$ROOT/scripts/quality-gate.sh
  must [ "$(grep -Ec 'docker-compose|docker compose' "$_gf" || true)" -eq 0 ]
  must [ "$(grep -Ec 'docker.*\|\| true' "$_gf" || true)" -eq 0 ]
}

t_gate_runs_s14_contract_unit_and_managed_check_for_squid_block() {
  _gf=$ROOT/scripts/quality-gate.sh
  must grep -Fxq '  run sh tests/s14-taskdef-contract.sh unit' "$_gf"
  must grep -Fq 'swsc_check_managed_empty' "$_gf"
  must [ "$(grep -c 's14-compose-port-binding' "$_gf" || true)" -eq 0 ]
}

# 品質ゲートの managed_check を、ゲートの定義から取り出して実行する。偽の docker の失敗が status=1 になることを確かめる。
t_managed_resource_check_failure() {
  managed_setup || return 1
  touch "$TMP/docker-fail"
  _fn=$(awk '/^managed_check\(\) \{/{f = 1} f {print} f && /^}/ {exit}' "$ROOT/scripts/quality-gate.sh")
  must [ -n "$_fn" ]
  # shellcheck disable=SC2016 # 単一引用符の中の $REPO_ROOT、$status、$repo_root は、env -i で起動した子の sh が展開する。親のシェルでは展開させない意図。
  _out=$(env -i PATH="$TMP/mbin:$TMP/mbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_TEST_DIR="$TMP" \
    REPO_ROOT="$ROOT" sh -c 'repo_root=$REPO_ROOT; status=0; '"$_fn"'; managed_check 試験 2>/dev/null; echo "$status"') || return 1
  must [ "$_out" = 1 ]
}

t_managed_resource_check_passes_when_empty_in_gate() {
  managed_setup || return 1
  _fn=$(awk '/^managed_check\(\) \{/{f = 1} f {print} f && /^}/ {exit}' "$ROOT/scripts/quality-gate.sh")
  must [ -n "$_fn" ]
  # shellcheck disable=SC2016 # 単一引用符の中の $REPO_ROOT、$status、$repo_root は、env -i で起動した子の sh が展開する。親のシェルでは展開させない意図。
  _out=$(env -i PATH="$TMP/mbin:$TMP/mbase" HOME="$TMP" SWSC_ROOT="$ROOT" SWSC_TEST_DIR="$TMP" \
    REPO_ROOT="$ROOT" sh -c 'repo_root=$REPO_ROOT; status=0; '"$_fn"'; managed_check 試験 2>/dev/null; echo "$status"') || return 1
  must [ "$_out" = 0 ]
}

t_gate_does_not_register_contract_and_states_why() {
  _gf=$ROOT/scripts/quality-gate.sh
  _n=$(grep -c '^  run .*m09-execution-and-ci\.sh contract' "$_gf" || true)
  must [ "$_n" -eq 0 ]
  must grep -Fq 'NOTE: tests/m09-execution-and-ci.sh contract は利用者の端末と CI だけで実行するため、ゲートでは実行しない' "$_gf"
}

t_gate_m09_block_has_no_aws_or_credentials() {
  _blk=$(gate_m09_block) || return 1
  _n=$(printf '%s\n' "$_blk" | grep -c 'AWS\|aws' || true)
  must [ "$_n" -eq 0 ]
}

t_gate_m09_is_not_added_to_the_existing_loop() {
  _gf=$ROOT/scripts/quality-gate.sh
  _n=$(grep '^  for test in' "$_gf" | grep -c m09 || true)
  must [ "$_n" -eq 0 ]
  must grep -Fxq '  for test in tests/m02-routing-smoke.sh tests/m03-wiremock-scenarios.sh tests/m04-test-client.sh tests/m05-proxy-integration.sh tests/m06-client-resilience.sh tests/m07-scenario-isolation.sh tests/m08-e2e-suite.sh; do' "$_gf"
}

# T2621: M02 は稼働中のスタックを前提にしなくなったため、ゲートの対象へ入れ、除外の NOTE を外す。
t_gate_m02_runs_in_gate_without_stack_note() {
  _gf=$ROOT/scripts/quality-gate.sh
  must grep -Fxq "if has_match '^(Dockerfile|squid-config/|wiremock-scenarios/|test-client/|tests/|scripts/scenario-lib\.sh)'; then" "$_gf"
  must [ "$(grep -c 'NOTE: tests/m02-routing-smoke.sh' "$_gf" || true)" -eq 0 ]
  must grep -Fq 'tests/m02-routing-smoke.sh' "$_gf"
}

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

t_lock_acquire_busy() {
  _d=$(lock_case_dir) || return 1
  _lock=$_d/ports.lock
  ( SWSC_LOCK_DIR=$_lock; . "$ROOT/scripts/e2e-lib.sh"; swsc_lock_acquire ) || return 1
  # shellcheck disable=SC2031 # _lock は本関数の冒頭で親のシェルが代入する。サブシェルは SWSC_LOCK_DIR に値を渡すだけで _lock を変えない。ここで読むのは親の値。
  must grep -Fxq "$$" "$_lock/owner"
  # shellcheck disable=SC2031 # _lock は本関数の冒頭で親のシェルが代入する。サブシェルは SWSC_LOCK_DIR に値を渡すだけで _lock を変えない。ここで読むのは親の値。
  if ( SWSC_LOCK_DIR=$_lock; . "$ROOT/scripts/e2e-lib.sh"; swsc_lock_acquire ) 2>"$TMP/busy.err"; then
    return 1
  fi
  must grep -Fq 'ls -ld' "$TMP/busy.err"
  must grep -Fq 'rmdir' "$TMP/busy.err"
  must grep -Fq "$$" "$TMP/busy.err"
  # shellcheck disable=SC2031 # _lock は本関数の冒頭で親のシェルが代入する。サブシェルは SWSC_LOCK_DIR に値を渡すだけで _lock を変えない。ここで読むのは親の値。
  must [ -f "$_lock/owner" ]
  lock_case_clear "$_d"
}

t_lock_release_non_owner() {
  _d=$(lock_case_dir) || return 1
  _lock=$_d/ports.lock
  _lib="$ROOT/scripts/e2e-lib.sh"
  # 読み込み先は scripts/e2e-lib.sh に固定されている。e2e-lib.sh は単独で検査するため、ここでは追わない。
  # Why: 23か所で追うと、shellcheck が e2e-lib.sh を毎回解析し、300秒で終わらず、1.6GBを使う。
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  if ( SWSC_LOCK_DIR=$_lock; . "$_lib"; swsc_lock_release ) >/dev/null 2>&1; then
    return 1
  fi
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  ( SWSC_LOCK_DIR=$_lock; . "$_lib"; swsc_lock_acquire ) || return 1
  printf '%s\n%s\n' 1 'other' >"$_lock/owner"
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  if ( SWSC_LOCK_DIR=$_lock; . "$_lib"; swsc_lock_release ) >/dev/null 2>&1; then
    return 1
  fi
  must [ -d "$_lock" ]
  must grep -Fxq 1 "$_lock/owner"
  printf '%s\n%s\n' "$$" 'self' >"$_lock/owner"
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  ( SWSC_LOCK_DIR=$_lock; . "$_lib"; swsc_lock_release ) || return 1
  must [ ! -e "$_lock" ]
  lock_case_clear "$_d"
}

t_check_ports_free() {
  _lib="$ROOT/scripts/e2e-lib.sh"
  # 読み込み先は scripts/e2e-lib.sh に固定されている。e2e-lib.sh は単独で検査するため、ここでは追わない。
  # Why: 23か所で追うと、shellcheck が e2e-lib.sh を毎回解析し、300秒で終わらず、1.6GBを使う。
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free 8080 3128 4566 ) || return 1
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free 1 65535 ) || return 1
  _calls=$TMP/calls.log
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  if ( . "$_lib"; swsc_port_in_use() { echo "$1" >>"$_calls"; [ "$1" = 3128 ]; }; swsc_check_ports_free 8080 3128 4566 ) 2>"$TMP/busy.err"; then
    return 1
  fi
  must grep -Fq 3128 "$TMP/busy.err"
  must [ "$(grep -c '' "$_calls")" -eq 3 ]
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  if ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free ) >/dev/null 2>&1; then return 1; fi
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  if ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free '' ) >/dev/null 2>&1; then return 1; fi
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  if ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free abc ) >/dev/null 2>&1; then return 1; fi
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  if ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free 0 ) >/dev/null 2>&1; then return 1; fi
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  if ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free 65536 ) >/dev/null 2>&1; then return 1; fi
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2329 # swsc_port_in_use は、. で読み込んだ e2e-lib.sh の swsc_check_ports_free が呼ぶ。この部分シェルの中だけで差し替える意図。
  if ( . "$_lib"; swsc_port_in_use() { return 1; }; swsc_check_ports_free 8080 abc ) >/dev/null 2>&1; then return 1; fi
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

t_client_once_env_rejects_control() {
  _d=$(lock_case_dir) || return 1
  _bin=$_d/bin
  _run=$_d/run
  _rec=$_d/rec
  _url=http://swsc-wiremock:8080/api
  _lib="$ROOT/scripts/e2e-lib.sh"
  t2602_fake_docker "$_bin"
  mkdir -p "$_run"
  # Why: --label の次の値を URL と取り違えないことを、引数の並びで確かめるため。
  printf '%s\n' --name swsc-client-R1 swsc-client:e2e --label keep-me >"$_run/swsc-client-R1.args"
  for _bad in '1ABC=x' 'BAD-NAME=x' '=x' 'NOEQ' "OK=$(printf 'a\nb')" "OK=$(printf 'a\tb')" "OK=$(printf 'a\033b')" "$(printf 'OK\n=x')"; do
    _rc=0
    # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
    # shellcheck source=/dev/null
    # shellcheck disable=SC2030 # PATH と SWSC_FAKE_REC は、このサブシェルの中だけで変える（fake docker を先頭に置き、記録先を渡す）。親の値は変わらず、後の行で読むのも親の値。
    (PATH="$_bin:$PATH"; export SWSC_FAKE_REC="$_rec"; . "$_lib"; swsc_client_once_env "$_run" R1 "$_url" "$_d/out" "$_d/err" "$_bad") >/dev/null 2>&1 || _rc=$?
    [ "$_rc" -eq 2 ] || return 1
    [ ! -e "$_rec" ] || return 1
  done
  # 前提が足りない（引数が少ない、出力先が空、実行ディレクトリが無い）ときも、docker を呼ばず 2 を返す。
  _rc=0
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_REC は、このサブシェルの中だけで変える（fake docker を先頭に置き、記録先を渡す）。親の値は変わらず、後の行で読むのも親の値。
  (PATH="$_bin:$PATH"; export SWSC_FAKE_REC="$_rec"; . "$_lib"; swsc_client_once_env "$_run" R1 "$_url") >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 2 ] || return 1
  _rc=0
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_REC は、このサブシェルの中だけで変える（fake docker を先頭に置き、記録先を渡す）。親の値は変わらず、後の行で読むのも親の値。
  (PATH="$_bin:$PATH"; export SWSC_FAKE_REC="$_rec"; . "$_lib"; swsc_client_once_env "$_run" R1 "$_url" "" "$_d/err") >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 2 ] || return 1
  _rc=0
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_REC は、このサブシェルの中だけで変える（fake docker を先頭に置き、記録先を渡す）。親の値は変わらず、後の行で読むのも親の値。
  (PATH="$_bin:$PATH"; export SWSC_FAKE_REC="$_rec"; . "$_lib"; swsc_client_once_env "$_d/none" R1 "$_url" "$_d/out" "$_d/err") >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 2 ] || return 1
  [ ! -e "$_rec" ] || return 1
  # 正常系。値は空白、引用符、$( ) を含むが、シェルで評価されず1要素で届く。
  _quoted="NAME_B=say \"hi\" 'x' \$(touch $_d/marker)"
  _rc=0
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_REC は、このサブシェルの中だけで変える（fake docker を先頭に置き、記録先を渡す）。親の値は変わらず、後の行で読むのも親の値。
  (PATH="$_bin:$PATH"; export SWSC_FAKE_REC="$_rec"; . "$_lib"; swsc_client_once_env "$_run" R1 "$_url" "$_d/out" "$_d/err" 'NAME_A=x y' "$_quoted" 'EMPTY_OK=' 'EQ=a=b') >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 0 ] || return 1
  printf '[%s]\n' run --rm -e 'NAME_A=x y' -e "$_quoted" -e 'EMPTY_OK=' -e 'EQ=a=b' -e "TEST_API_BASE_URL=$_url" \
    --name swsc-client-R1 swsc-client:e2e --label keep-me >"$_d/expected"
  cmp -s "$_rec" "$_d/expected" || return 1
  [ ! -e "$_d/marker" ] || return 1
  # 標準出力と標準エラーは、別のファイルに分かれて保存される。
  grep -Fxq client-stdout "$_d/out" || return 1
  grep -Fxq client-stderr "$_d/err" || return 1
  if grep -Fq client-stderr "$_d/out"; then return 1; fi
  if grep -Fq client-stdout "$_d/err"; then return 1; fi
  # Client の終了コードは、そのまま返す。
  _rc=0
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_REC は、このサブシェルの中だけで変える（fake docker を先頭に置き、記録先を渡す）。親の値は変わらず、後の行で読むのも親の値。
  (PATH="$_bin:$PATH"; export SWSC_FAKE_REC="$_rec" SWSC_FAKE_RC=7; . "$_lib"; swsc_client_once_env "$_run" R1 "$_url" "$_d/out" "$_d/err") >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 7 ] || return 1
  lock_case_clear "$_d"
}

t_wiremock_count_path() {
  _d=$(lock_case_dir) || return 1
  _bin=$_d/bin
  _body=$_d/body.json
  _lib="$ROOT/scripts/e2e-lib.sh"
  t2602_fake_curl "$_bin"
  # 応答を書き、経路の件数を求める。結果は _out（標準出力）と _rc（終了コード）へ入れる。
  _count() { # 応答 経路
    printf '%s' "$1" >"$_body"
    _rc=0
    # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
    # shellcheck source=/dev/null
    # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_BODY は、このサブシェルの中だけで変える（fake curl を先頭に置き、応答を渡す）。親の値は変わらず、ここで読むのも親の値。
    _out=$( (PATH="$_bin:$PATH"; export SWSC_FAKE_BODY="$_body"; . "$_lib"; swsc_wiremock_count_path "$2") 2>/dev/null) || _rc=$?
  }
  # /api/users/123 だけを数える。/api/users/1234、/api/users/123/x、Squid の内部要求は数えない。
  _a='{"meta":{"total":5},"requests":[{"request":{"url":"/api/users/123"}},{"request":{"url":"/api/users/1234"}},{"request":{"url":"/api/users/123/x"}},{"request":{"url":"/squid-internal-periodic/store_digest"}},{"request":{"url":"/api/users/123"}}]}'
  _count "$_a" /api/users/123
  [ "$_rc" -eq 0 ] && [ "$_out" = 2 ] || return 1
  _count "$_a" /squid-internal-periodic/store_digest
  [ "$_rc" -eq 0 ] && [ "$_out" = 1 ] || return 1
  _count "$_a" /api/users/999
  [ "$_rc" -eq 0 ] && [ "$_out" = 0 ] || return 1
  # 空のジャーナルは 0 を返す。
  _count '{"meta":{"total":0},"requests":[]}' /api/users/123
  [ "$_rc" -eq 0 ] && [ "$_out" = 0 ] || return 1
  # meta.total と requests[] が食い違う、URL が文字列でない、JSON でない、は数えずに 1。
  _count '{"meta":{"total":3},"requests":[{"request":{"url":"/api/users/123"}}]}' /api/users/123
  [ "$_rc" -eq 1 ] || return 1
  _count '{"meta":{"total":1},"requests":[{"request":{"url":5}}]}' /api/users/123
  [ "$_rc" -eq 1 ] || return 1
  _count 'not json' /api/users/123
  [ "$_rc" -eq 1 ] || return 1
  # 管理 API の取得に失敗したときは 1。
  _rc=0
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_BODY は、このサブシェルの中だけで変える（fake curl を先頭に置き、失敗応答を渡す）。親の値は変わらず、後の行で読むのも親の値。
  (PATH="$_bin:$PATH"; export SWSC_FAKE_BODY="$_body" SWSC_FAKE_CURL_FAIL=1; . "$_lib"; swsc_wiremock_count_path /api/users/123) >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 1 ] || return 1
  # 経路は python のコードに埋め込まれず引数で渡る。注入の文字列は一致せず、何も実行されない。
  _count "$_a" "/api/x'); import os; os.system('touch $_d/marker')"
  [ "$_rc" -eq 0 ] && [ "$_out" = 0 ] || return 1
  [ ! -e "$_d/marker" ] || return 1
  # 経路が無いときは 1。
  _rc=0
  # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
  # shellcheck source=/dev/null
  # shellcheck disable=SC2030,SC2031 # PATH と SWSC_FAKE_BODY は、このサブシェルの中だけで変える（fake curl を先頭に置き、応答を渡す）。親の値は変わらず、後の行で読むのも親の値。
  (PATH="$_bin:$PATH"; export SWSC_FAKE_BODY="$_body"; . "$_lib"; swsc_wiremock_count_path) >/dev/null 2>&1 || _rc=$?
  [ "$_rc" -eq 1 ] || return 1
  lock_case_clear "$_d"
}

t_squid_log_check() {
  # Why: 検査が読む access log のパスが、設定ファイルの access_log と同じであることを確かめる。
  grep -Eq '^access_log /var/log/squid/access.log( |$)' "$ROOT/squid-config/squid.conf" || return 1
  _d=$(lock_case_dir) || return 1
  _bin=$_d/bin
  _rec=$_d/rec
  _log=$_d/access.log
  _lib="$ROOT/scripts/e2e-lib.sh"
  t2602_fake_docker "$_bin"
  # 記録には * を含まず、$( ) はそのまま文字列として含む。
  # shellcheck disable=SC2016 # 書き出すアクセスログの本文として $( ) を文字どおり書く。コマンドとして実行されず、検査が拒否することを確かめる意図。
  printf 'GET /api/users/123 200 $(touch %s/marker);\n' "$_d" >"$_log"
  # 検査の1回。結果は _rc（終了コード）と、標準エラーの $_d/err へ入れる。
  _slog() { # パターン...
    _rc=0
    # 読み込み先は scripts/e2e-lib.sh。単独で検査するため追わない（plan 4.4節の注）。
    # shellcheck source=/dev/null
    # shellcheck disable=SC2031 # PATH と SWSC_FAKE_REC は、このサブシェルの中だけで変える（fake docker を先頭に置き、記録先を渡す）。親の値は変わらず、ここで読むのも親の値。
    (PATH="$_bin:$PATH"; export SWSC_FAKE_REC="$_rec" SWSC_FAKE_LOG="$_log"; . "$_lib"; swsc_squid_log_check "$@") >/dev/null 2>"$_d/err" || _rc=$?
  }
  _slog /api/users/123 200
  [ "$_rc" -eq 0 ] || return 1
  grep -Fxq '[swsc-squid]' "$_rec" || return 1
  grep -Fxq '[/var/log/squid/access.log]' "$_rec" || return 1
  _slog /api/users/123 /missing
  [ "$_rc" -eq 1 ] || return 1
  grep -Fq '一致しない' "$_d/err" || return 1
  if grep -Fq '取得できない' "$_d/err"; then return 1; fi
  # パターンは固定文字列。* は一致せず、$( ) はコマンドとして実行されない。
  _slog '*'
  [ "$_rc" -eq 1 ] || return 1
  _slog 'a;b'
  [ "$_rc" -eq 1 ] || return 1
  _slog "\$(touch $_d/marker)"
  [ "$_rc" -eq 0 ] || return 1
  [ ! -e "$_d/marker" ] || return 1
  # 引数が無い、空のパターン、改行を含むパターンは 1。
  _slog
  [ "$_rc" -eq 1 ] || return 1
  _slog ''
  [ "$_rc" -eq 1 ] || return 1
  _slog "$(printf '200\n/api')"
  [ "$_rc" -eq 1 ] || return 1
  # docker exec の失敗は、不一致と区別できる文言で 1 を返す。
  export SWSC_FAKE_EXEC_FAIL=1
  _slog /api/users/123
  unset SWSC_FAKE_EXEC_FAIL
  [ "$_rc" -eq 1 ] || return 1
  grep -Fq '取得できない' "$_d/err" || return 1
  if grep -Fq '一致しない' "$_d/err"; then return 1; fi
  lock_case_clear "$_d"
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

t_managed_empty_passes_when_nothing_is_left() {
  managed_setup || return 1
  _rc=0
  managed_run 'swsc_check_managed_empty' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
}

t_managed_empty_fails_and_names_labelled_prefixed_leftovers() {
  managed_setup || return 1
  printf 'swsc-squid\n' >"$TMP/lab-ps"
  printf 'swsc-net\n' >"$TMP/lab-net"
  _rc=0
  managed_run 'swsc_check_managed_empty' >/dev/null 2>"$TMP/err" || _rc=$?
  must [ "$_rc" -eq 1 ]
  must grep -Fq 'swsc-squid' "$TMP/err"
  must grep -Fq 'swsc-net' "$TMP/err"
}

t_managed_empty_ignores_label_only_and_prefix_only() {
  managed_setup || return 1
  printf 'm05-app\n' >"$TMP/lab-ps"
  printf 'swsc-unlabelled\n' >"$TMP/all-ps"
  printf 'm05-net\n' >"$TMP/lab-net"
  printf 'swsc-foreign\n' >"$TMP/all-net"
  _rc=0
  managed_run 'swsc_check_managed_empty' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
}

t_managed_empty_docker_failure_is_not_reported_as_empty() {
  managed_setup || return 1
  touch "$TMP/docker-fail"
  _rc=0
  managed_run 'swsc_check_managed_empty' >/dev/null 2>"$TMP/err" || _rc=$?
  must [ "$_rc" -eq 1 ]
  must grep -Fq '確かめられ' "$TMP/err"
}

t_runner_labels_network_has_prefix_and_label() {
  runner_setup || return 1
  runner_run 'swsc_runner_create_network' >/dev/null 2>&1 || return 1
  must grep -qxF 'docker network create --label swsc.managed=true swsc-net' "$TMP/seq.log"
}

# T2603: 入口のロックと trap。ロックは検査専用の場所（UNIT_LOCK）にだけ作る。
# Why: 実ホストの /tmp/swsc-e2e-ports.lock を検査が取ると、利用中の実行と衝突するため。
# 他者のロックは、取り残しを模して owner を書いた mkdir で作る。
lock_busy_setup() {
  mkdir "$UNIT_LOCK" || return 1
  printf '%s\n%s\n' 99999 other >"$UNIT_LOCK/owner"
}

t_entry_trap_exit_143_start_refuses_when_locked() {
  entry_setup || return 1
  lock_busy_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # lib_call に渡す関数定義の文字列。$SWSC_TEST_SEQ は、lib_call の子の sh で関数を実行するときに展開する。親では展開させない意図。
  lib_call 'swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; }; swsc_start_op' >/dev/null 2>"$TMP/err" || _rc=$?
  must [ "$_rc" -eq 1 ]
  must [ ! -s "$TMP/seq.log" ]
  must grep -Fq 'ロック' "$TMP/err"
  must grep -Fxq other "$UNIT_LOCK/owner"
}

t_entry_trap_exit_143_start_releases_lock_on_success_and_failure() {
  entry_setup || return 1
  _rc=0
  lib_call "$CI_FAKES; swsc_start_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must [ ! -e "$UNIT_LOCK" ]
  printf 1 >"$TMP/rc-start"
  rm -f "$TMP/seq.log"
  _rc=0
  lib_call "$CI_FAKES; swsc_start_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must [ ! -e "$UNIT_LOCK" ]
  must seq_is "$(printf 'start\nstop')"
}

t_entry_trap_exit_143_start_term_stops_then_releases_lock() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # lib_call に渡す関数定義の文字列。$SWSC_TEST_SEQ と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へ TERM を送るための意図。親の PID にはしない。
  lib_call 'swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; kill -TERM $$; return 0; }
swsc_stop() { if [ -d "$SWSC_LOCK_DIR" ]; then echo stop-held >>"$SWSC_TEST_SEQ"; fi; }
swsc_start_op' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 143 ]
  must seq_is "$(printf 'start\nstop-held')"
  must [ ! -e "$UNIT_LOCK" ]
}

t_entry_trap_exit_143_start_busy_port_creates_nothing_and_releases() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # lib_call に渡す関数定義の文字列。$1 は、lib_call の子の sh で関数の引数を読むときに展開する。親では展開させない意図。
  lib_call 'swsc_port_in_use() { [ "$1" = 3128 ]; }
swsc_stop() { echo stop >>"$SWSC_TEST_SEQ"; }
swsc_build_images() { echo build >>"$SWSC_TEST_SEQ"; }
swsc_start_op' >/dev/null 2>"$TMP/err" || _rc=$?
  must [ "$_rc" -eq 1 ]
  must grep -Fq '3128' "$TMP/err"
  # Why: 停止は start_main の先頭と、失敗時の後始末で1回ずつ呼ばれる。build には進まない。
  must seq_is "$(printf 'stop\nstop')"
  must [ ! -e "$UNIT_LOCK" ]
}

t_entry_trap_exit_143_test_ci_takes_lock_once_and_releases_after_stop() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # lib_call に渡す関数定義の文字列。$SWSC_TEST_SEQ と $SWSC_LOCK_HELD は、lib_call の子の sh で関数を実行するときに展開する。親では展開させない意図。
  lib_call 'swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; if [ "${SWSC_LOCK_HELD:-0}" = 1 ]; then echo held-in-start >>"$SWSC_TEST_SEQ"; fi; return 0; }
swsc_test_run() { echo test >>"$SWSC_TEST_SEQ"; return 0; }
swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; return 0; }
swsc_stop() { if [ -d "$SWSC_LOCK_DIR" ]; then echo stop-held >>"$SWSC_TEST_SEQ"; fi; }
swsc_test_ci_main' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must seq_is "$(printf 'start\nheld-in-start\ntest\ncollect\nstop-held')"
  must [ ! -e "$UNIT_LOCK" ]
}

t_entry_trap_exit_143_test_ci_refuses_when_locked() {
  entry_setup || return 1
  lock_busy_setup || return 1
  _rc=0
  lib_call "$CI_FAKES; swsc_test_ci_main" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must [ ! -s "$TMP/seq.log" ]
  must grep -Fxq other "$UNIT_LOCK/owner"
}

t_entry_trap_exit_143_test_ci_int_releases_after_stop() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # lib_call に渡す関数定義の文字列。$SWSC_TEST_SEQ と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へ INT を送るための意図。親の PID にはしない。
  lib_call 'swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; kill -INT $$; return 0; }
swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; }
swsc_stop() { if [ -d "$SWSC_LOCK_DIR" ]; then echo stop-held >>"$SWSC_TEST_SEQ"; fi; }
swsc_test_ci_main' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 130 ]
  must seq_is "$(printf 'start\ncollect\nstop-held')"
  must [ ! -e "$UNIT_LOCK" ]
}

t_entry_trap_exit_143_test_ci_term_releases_after_stop() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # lib_call に渡す関数定義の文字列。$SWSC_TEST_SEQ と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へ TERM を送るための意図。親の PID にはしない。
  lib_call 'swsc_start_main() { echo start >>"$SWSC_TEST_SEQ"; kill -TERM $$; return 0; }
swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; }
swsc_stop() { if [ -d "$SWSC_LOCK_DIR" ]; then echo stop-held >>"$SWSC_TEST_SEQ"; fi; }
swsc_test_ci_main' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 143 ]
  must seq_is "$(printf 'start\ncollect\nstop-held')"
  must [ ! -e "$UNIT_LOCK" ]
}

t_entry_trap_exit_143_test_op_term_releases_lock() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # lib_call に渡す関数定義の文字列。$SWSC_TEST_SEQ と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へ TERM を送るための意図。親の PID にはしない。
  lib_call 'swsc_test_run() { echo test >>"$SWSC_TEST_SEQ"; kill -TERM $$; return 0; }
swsc_stop() { if [ -d "$SWSC_LOCK_DIR" ]; then echo stop-held >>"$SWSC_TEST_SEQ"; fi; }
swsc_test_op' >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 143 ]
  must seq_is "$(printf 'test\nstop-held')"
  must [ ! -e "$UNIT_LOCK" ]
}

t_entry_trap_exit_143_test_op_refuses_when_locked() {
  entry_setup || return 1
  lock_busy_setup || return 1
  _rc=0
  lib_call "$CI_FAKES; swsc_test_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must [ ! -s "$TMP/seq.log" ]
  must grep -Fxq other "$UNIT_LOCK/owner"
}

# stop、clean、logs は、ロックが残っていても動き、ロックには触れない。
t_entry_trap_exit_143_stop_clean_logs_ignore_lock() {
  entry_setup || return 1
  lock_busy_setup || return 1
  entry_run stop >/dev/null 2>&1 || return 1
  entry_run clean >/dev/null 2>&1 || return 1
  entry_run logs squid >/dev/null 2>&1 || return 1
  must grep -Fxq other "$UNIT_LOCK/owner"
}

t_entry_trap_exit_143_contract_refuses_busy_4566_and_releases() {
  contract_setup || return 1
  # shellcheck disable=SC2016 # contract_go に渡す関数定義の文字列。$1 は、子の sh で関数の引数を読むときに展開する。親では展開させない意図。
  contract_go 'swsc_port_in_use() { [ "$1" = 4566 ]; }; swsc_collect() { :; }; contract_main'
  must [ "$RC" -eq 1 ]
  must [ -z "$(seq_line 'docker run')" ]
  must [ -z "$(seq_line 'aws ')" ]
  must [ ! -e "$UNIT_LOCK" ]
}

t_entry_trap_exit_143_contract_refuses_when_locked() {
  contract_setup || return 1
  lock_busy_setup || return 1
  contract_go "$CONTRACT_FREE; swsc_collect() { :; }; contract_main"
  must [ "$RC" -eq 1 ]
  must [ -z "$(seq_line 'docker run')" ]
  must [ -z "$(seq_line 'aws ')" ]
  must grep -Fxq other "$UNIT_LOCK/owner"
}

t_entry_trap_exit_143_contract_term_releases_lock() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; swsc_contract_wait_ready() { if [ -d \"\$SWSC_LOCK_DIR\" ]; then echo held >>\"\$SWSC_TEST_SEQ\"; fi; kill -TERM \$\$; return 0; }; swsc_collect() { :; }; contract_main"
  must [ "$RC" -eq 143 ]
  must grep -qxF held "$TMP/seq.log"
  must [ ! -e "$UNIT_LOCK" ]
}

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
  check '不正なモードと余計な引数は終了コード2' t_usage_rejects_bad_arguments
  check 'package.json の6つのscriptsがe2e.shへ委譲する' t_package_json_delegates_six_scripts
  check '.gitignoreに.e2e/とe2e-logs/がある' t_gitignore_hides_run_outputs
  check '操作なしは終了コード2' t_entry_without_operation_exits_2
  check '未知の操作は終了コード2' t_entry_unknown_operation_exits_2
  check 'test:ci の不明なシナリオ名は、ロックと起動の前に終了コード2' t_test_ci_unknown_scenario_exits_2_before_docker
  check 'test:ci の名前指定は、子の終了コードを返し、ロックを解放する' t_test_ci_scenarios_returns_child_rc_and_releases_lock
  check 'test:ci の名前指定の TERM は143で、子を止めてからロックを解放する' t_test_ci_scenarios_term_stops_child_and_releases_lock
  check 'logsは追加の引数を受けても引数誤りにならない' t_logs_accepts_extra_arguments
  check 'startはdockerが無いと原因を示して止まる' t_start_without_docker_names_docker
  check 'contractは認証情報が無いと docker と aws を呼ばずに止まる' t_contract_without_credentials_stops_before_docker_and_aws
  check 'contractは test 以外の認証情報を拒否する' t_contract_rejects_non_dummy_credentials
  check 'contractは AWS_PROFILE を拒否する' t_contract_rejects_aws_profile
  check 'contractはダミー認証情報があれば前提を通り、最初に既存のswsc-ministackを消す' t_contract_with_dummy_credentials_removes_old_ministack_first
  check 'awsを呼ぶ行はswsc_awsの1か所だけ' t_only_swsc_aws_calls_aws
  check 'FR-920の検出がコマンドの形を捕まえる' t_fr920_detector_catches_command_forms
  check 'FR-920の検出がコメントと語を誤検出しない' t_fr920_detector_allows_comments_and_words
  check 'M09の対象ファイルにdocker-composeの呼び出しが無い' t_fr920_holds_for_m09_files
  check '前提検査にポートの確認を含めない' t_prereq_for_smoke_has_no_port_check
  printf '== T908 テンプレートと生成\n'
  check 'テンプレートは2コンテナのJSONで、awsvpc' t_template_is_valid_json_with_two_containers
  check '生成の結果はローカルのSquidにmockの宛先を渡す' t_render_local_sets_upstream_and_mock_destination
  check '同じ入力から同じバイト列になる' t_render_is_byte_identical_for_same_input
  check '未知のプレースホルダーは名前を示して失敗する' t_render_fails_on_unknown_placeholder_and_names_it
  check '置換されずに残った形式（小文字）は失敗する' t_render_fails_on_leftover_placeholder_in_key_or_value
  check '許可リスト外の項目（volumes）は名指しで失敗する' t_render_rejects_disallowed_key_by_name
  check 'dependsOnの条件はSTARTかHEALTHYだけ' t_render_rejects_dependency_condition_other_than_start_or_healthy
  check 'healthCheckのCMD-SHELL以外は失敗する' t_render_rejects_health_check_that_is_not_cmd_shell
  check '値の文字種違反は値を出さずに失敗する' t_render_rejects_malformed_values_without_printing_them
  check 'タスクレベルの固定値、ロールARNを書かない' t_render_fixes_task_level_values_and_omits_roles
  check 'Clientのプロキシ設定があり、healthCheckが無い' t_client_has_proxy_settings_and_no_health_check
  check 'テンプレートにmockの既定値とロールARNが無い' t_template_names_no_mock_default_or_role_arn
  check '完成版の生成はswsc_renderの1か所に集まる' t_swsc_render_is_the_only_generation_path
  check 'swsc_render経由の出力は直接の生成と一致する' t_swsc_render_matches_direct_render
  printf '== T909 本番向けの検査\n'
  check '層1: テンプレートにmockの既定値とSQUID_MOCK_が無い' t_template_layer1_has_no_mock_default
  check '本番向けはdirectで生成でき、検査に通る' t_production_render_with_direct_passes_check
  check '本番向けはdirect以外の上流を拒否する（大文字、空白、空を含む）' t_production_render_rejects_upstream_other_than_direct
  check '本番向けはWireMockの宛先の指定を拒否する' t_production_render_rejects_mock_destination
  check 'check-productionは上流の各種の誤りを拒否し、値を出さない' t_check_production_rejects_each_upstream_variant
  check 'check-productionはSQUID_UPSTREAMの欠落を拒否する' t_check_production_rejects_missing_upstream
  check 'check-productionはSQUID_MOCK_の残存を拒否する' t_check_production_rejects_leftover_mock_destination
  check 'check-productionは読めない入力で終了コード2' t_check_production_exit_2_when_unreadable
  check '入口のcheck-productionの終了コードが検査の結果と一致する' t_entry_check_production_exit_codes
  printf '== T910 Squid のイメージ\n'
  check '派生: 未設定を拒否する' t_derive_rejects_unset_upstream
  check '派生: 上流の値の変形（大文字、空白、空）を拒否する' t_derive_rejects_upstream_variants
  check '派生: mockは宛先の1行だけを変える' t_derive_mock_rewrites_only_the_peer_line
  check '派生: directはピアの行を除き always_direct を足す' t_derive_direct_removes_peer_lines_and_adds_always_direct
  check '派生: directはSQUID_MOCK_を無視する' t_derive_direct_ignores_mock_destination
  check '派生: 宛先ホストへの注入になる値を拒否する' t_derive_mock_rejects_host_injection
  check '派生: 宛先ポートの範囲外と非数字を拒否する' t_derive_mock_rejects_bad_port
  check '派生: 宛先ポートの境界値（1、9999、10000、65535）を受理する' t_derive_mock_accepts_port_boundaries
  check '派生: 派生元の必須の行が欠けたら失敗する' t_derive_rejects_source_without_each_required_line
  check '派生: 派生元の必須の行が重複したら失敗する' t_derive_rejects_duplicated_required_line
  check 'Dockerfile: ubuntu/squid:latest から作り、名前を揃える' t_dockerfile_builds_from_ubuntu_squid_latest
  check 'エントリポイント: 派生、parse、表示、exec の順' t_entrypoint_orders_derive_parse_report_exec
  check 'エントリポイント: directで parse の後に元のエントリポイントへ渡す' t_entrypoint_direct_runs_parse_then_hands_over
  check 'エントリポイント: 上流が不正なら squid を呼ばずに止まる' t_entrypoint_stops_before_squid_when_upstream_invalid
  check 'ビルド文脈は元の設定と一致し、5ファイルだけ' t_squid_context_is_a_byte_copy_of_sources
  check 'シェルの構文とPythonの構文が通る' t_shell_syntax_and_python_compile_pass
  printf '== T911 MiniStackの契約検証\n'
  check 'swsc_awsはダミー認証情報が無い、またはtest以外なら呼ばずに止まる' t_swsc_aws_refuses_missing_or_non_dummy_credentials
  check 'swsc_awsは接続先と地域を明示し、設定元を外し、時間制限を付ける' t_swsc_aws_passes_endpoint_region_and_clears_config_sources
  check 'ポート確認は、接続できないポートを空きと判定する' t_port_check_reports_closed_port_as_free
  check '識別情報のマスクは12桁とARNを消し、16進の値は残す' t_mask_masks_account_and_arn_and_keeps_hex_hash
  check '比較は順序差と空の既定値を一致とみなす' t_compare_accepts_reordered_env_and_empty_defaults
  check '比較はイメージの変更を不一致にする' t_compare_fails_on_image_change
  check '比較は環境変数の値の変更を不一致にし、値を出さない' t_compare_fails_on_environment_value_and_does_not_print_it
  check '比較はessentialの変更を不一致にする' t_compare_fails_on_essential_change
  check '比較はポートの変更を不一致にする' t_compare_fails_on_port_change
  check '比較はdependsOnの変更を不一致にする' t_compare_fails_on_depends_on_change
  check '比較はhealthCheckの変更を不一致にする' t_compare_fails_on_health_check_change
  check '比較はコンテナ数の変更を不一致にする' t_compare_fails_on_container_count_change
  check '比較はnetworkModeの変更を不一致にする' t_compare_fails_on_network_mode_change
  check 'contractは成功時、登録とdescribeの後に、最後に後始末する' t_contract_success_registers_describes_and_removes_last
  check 'contractの完成版はswsc_renderの出力と一致する' t_contract_taskdef_is_the_swsc_render_output
  check 'MiniStackの起動はlocalhostだけに公開し、ソケット、特権、latestを使わない' t_contract_run_line_is_localhost_only_socketless_and_pinned
  check 'ポートが使用中なら、MiniStackの起動の前に止まる' t_contract_port_in_use_stops_before_docker_run
  check '既存のswsc-ministackの削除は、ポート確認より前に行う' t_contract_removes_old_ministack_before_port_check
  check 'ラベルの無い同名コンテナは、消さずに起動の段階で止まる' t_contract_never_removes_a_same_name_container_without_the_label
  check 'MiniStackの起動に失敗したら、awsを呼ばずに後始末する' t_contract_stops_when_docker_run_fails_without_aws_calls
  check 'MiniStackが応答しなければ起動待ちで止まり、登録しない' t_contract_stops_when_ministack_never_answers
  check '登録の失敗は段階名を示して止まる' t_contract_stops_at_registration_and_names_the_stage
  check '比較の不一致は段階名を示して後始末する' t_contract_mismatch_names_the_stage_and_removes
  check '失敗時はcollectを後始末より前に呼ぶ' t_contract_collects_on_failure_before_removal
  check '失敗時にcollectが無くても後始末する' t_contract_failure_without_collect_still_removes
  check '成功時はcollectを呼ばない' t_contract_success_never_collects
  check 'INTは終了コード130で、後始末をしてから止まる' t_contract_interrupt_exits_130_and_removes
  check 'TERMは終了コード143で、後始末をしてから止まる' t_contract_terminate_exits_143_and_removes
  check 'inspectの保存はマスクされ、公開ポートは127.0.0.1だけ' t_contract_saves_masked_inspect_with_only_localhost_port
  check 'describeは取り出す項目だけを求める' t_contract_describe_asks_only_the_listed_items
  check 'C4は、EXPOSEだけで公開していないポート（null）を数えない' t_contract_c4_accepts_exposed_but_unpublished_ports
  check 'C4は、2つ目の公開ポート、127.0.0.1以外の公開、ソケット、公開なしを拒否する' t_contract_c4_rejects_a_second_published_port_a_wider_bind_and_the_socket
  printf '== T912 pause方式のランナー\n'
  check 'docker-argsは各コンテナの引数、.env、依存を書く' t_docker_args_writes_args_and_env_for_each_container
  check 'docker-argsは先頭が - の image を拒否する' t_docker_args_rejects_image_that_starts_with_dash
  check 'docker-argsは後ろのコンテナに制御文字があれば、何も書かない' t_docker_args_writes_nothing_when_a_later_container_has_a_control_character
  check 'WireMockの待機は、コンテナが止まっていれば上限を待たずに止まる' t_runner_wait_wiremock_fails_fast_when_the_container_stopped
  check 'healthyの待機は、コンテナが止まっていれば上限を待たずに止まる' t_runner_wait_healthy_fails_fast_when_the_container_stopped
  check 'Squidの待受の確認は、コンテナが止まっていれば上限を待たずに止まる' t_runner_probe_squid_fails_fast_when_the_container_stopped
  check 'test:ciはcollectの最中にTERMを受けても、stopまで行う' t_test_ci_signal_during_collect_still_stops
  check '環境変数の値は引数に出ず、.env は0600' t_docker_args_keeps_env_values_out_of_args_and_private_file
  check '改行を含む値は失敗する' t_docker_args_rejects_newline_in_value
  check '変換の対象外（COMPLETE、CMD、ポート重複、bridge）は失敗する' t_docker_args_rejects_items_outside_the_conversion
  check 'ヘルスチェックをdockerのオプションへ変換する' t_docker_args_translates_health_check_to_docker_options
  check '名前とラベルを持ち、特権、ソケット、公開を持たない' t_docker_args_names_labels_and_forbids_host_privileges
  check '起動順はWireMock、管理APIの応答、pause、Squid' t_runner_start_orders_wiremock_admin_check_pause_squid
  check 'WireMockが応答しなければpauseとSquidを作らない' t_runner_creates_no_pause_or_squid_when_wiremock_never_ready
  check 'Squidはhealthyの後に、pauseの名前空間から待受を確かめる' t_runner_waits_for_squid_health_before_probing
  check '作るコンテナは全てswsc-の名前とラベルを持つ' t_runner_every_created_container_has_prefix_and_label
  check 'Clientはpauseの名前空間に参加し、終了コードを返す' t_runner_client_joins_pause_namespace_and_returns_its_exit_code
  check '後始末は接頭辞とラベルの両方が一致するものだけを消し、Squidを先に消す' t_runner_remove_managed_removes_only_prefixed_labelled_containers_in_order
  check 'WireMockの受信数は /api/ で始まるURLだけを数える' t_wiremock_total_counts_only_api_urls
  printf '== T913 入口の完成\n'
  check '起動の前提は aws と認証情報を要求しない（前提不足を出さず、awsを呼ばない）' t_start_prereq_skips_aws_and_credentials
  check 'testとtest:ciの前提は aws と認証情報を要求しない' t_test_and_test_ci_prereq_skip_aws_and_credentials
  check 'start、test、stop、clean、collect、test:ci は aws を呼ばない' t_stop_clean_collect_start_test_never_call_aws
  check '全操作で docker-compose を呼ばない' t_all_operations_never_call_docker_compose
  check 'ポート確認は自分のswsc-を止めた後、構築の前に行い、使用中なら旧基盤を示して止まる' t_start_checks_port_after_own_stop_and_before_build
  check 'start_mainはtrapを持たない' t_start_main_has_no_trap
  check 'stopは冪等で、接頭辞とラベルの両方が一致するものだけ消す' t_stop_is_idempotent_and_removes_only_prefixed_labelled
  check 'cleanは自分のイメージ2つと一時物だけを消す' t_clean_removes_only_own_images_and_dirs
  check 'cleanは目印の無いディレクトリを消さずに失敗する' t_clean_refuses_directories_without_the_marker
  check 'cleanは片方が拒否されても、目印のあるもう片方は消す' t_clean_still_removes_the_marked_directory_when_the_other_is_refused
  check 'cleanはシンボリックリンクの出力先を辿らない' t_clean_does_not_follow_a_symlink_output_dir
  check 'collectは目印の無いログ先に触れずに失敗する' t_collect_refuses_a_foreign_log_dir_and_leaves_it_untouched
  check 'collectは新しいログ先に目印を置き、再実行できる' t_collect_marks_a_new_log_dir_and_reuses_it
  check '出力先の用意は、空、/、相対パス、シンボリックリンクを拒否する' t_prepare_dir_rejects_empty_root_relative_and_symlink
  check '出力先の用意は、無いディレクトリと空のディレクトリを受け入れる' t_prepare_dir_accepts_missing_and_empty_directories
  check 'startは目印の無い出力先を、ビルドの前に拒否する' t_start_refuses_a_foreign_e2e_dir_before_building
  check 'logsは名前を swsc- に写し、未知の名前を終了コード2にする' t_logs_maps_name_to_prefixed_container_and_rejects_unknown
  check 'test:ciは成功時に start、test、collect、stop の順で1回ずつ呼ぶ' t_test_ci_success_runs_start_test_collect_stop_once
  check 'test:ciは start失敗でも collect を stop より前に呼び、rcを保つ' t_test_ci_start_failure_collects_then_stops_and_keeps_rc
  check 'test:ciは testの終了コードを保つ' t_test_ci_test_failure_keeps_test_rc_and_collects
  check 'test:ciは collect の失敗で終了コードを変えない' t_test_ci_collect_failure_does_not_change_rc
  check 'test:ciのINTは130で、collectとstopを通る' t_test_ci_interrupt_exits_130_and_still_collects_and_stops
  check 'test:ciのTERMは143で、collectとstopを通る' t_test_ci_terminate_exits_143_and_still_collects_and_stops
  check 'start操作は失敗時に stop だけを呼び、collect を呼ばない' t_start_op_failure_stops_without_collect
  check 'start操作は成功時に環境を残す（stopを呼ばない）' t_start_op_success_keeps_environment
  check 'test操作は通常の失敗で環境を残す' t_test_op_failure_keeps_environment
  check 'test操作のINTは130で、stopを呼ぶ' t_test_op_interrupt_stops_and_exits_130
  check 'testはSquidが稼働していなければClientを起動せず止まる' t_test_stops_without_client_when_squid_not_running
  check 'collectは対象が無くても0で、missing.txtに名前を残す' t_collect_without_containers_exits_0_and_records_missing
  check 'collectはコンテナのログ、Squidのログ、完成版を集める' t_collect_gathers_container_logs_squid_logs_and_files
  check 'collectは冪等で、元が無い回は既存の収集物を消さない' t_collect_is_idempotent_and_keeps_existing_when_source_missing
  check 'collectはARNと12桁のアカウントIDをコピーの上でマスクする' t_collect_masks_arn_and_account_in_copies
  check 'collectはUUIDの末尾の12桁を識別情報として扱わない' t_collect_does_not_treat_uuid_tail_as_account
  check 'collectはマスクで消せないファイルを削除し、scrub.txtに記録する。2回目は0' t_collect_removes_unmaskable_records_scrub_and_second_run_is_0
  check 'testは出力をログのファイルへ残す' t_test_run_writes_output_to_log_files
  check '検査の1件は、ステータスと受信数の両方が期待どおりなら合格' t_test_item_compares_status_and_wiremock_count
  check 'Clientのベースurlは引数の組み立ての影響を受けずに docker run へ届く' t_client_once_passes_base_url_unchanged
  check 'WireMockの受信記録の消去は DELETE /__admin/requests を使う' t_wiremock_reset_uses_delete_requests
  printf '== T914 実通信の検査（smoke と contract のモード）\n'
  check 'smokeの項目は表のとおり1から11の順に登録されている' t_smoke_registers_items_1_to_11_in_order
  check 'contractの項目は表のとおりC1からC6の順に登録されている' t_contract_registers_c1_to_c6_in_order
  check 'smokeはunitを、Dockerを呼ぶ前に実行する' t_smoke_runs_unit_before_docker
  check 'contractは認証情報が無いと、unit、Docker、AWS CLIを呼ばずに止まる' t_contract_precheck_stops_before_unit_docker_aws
  printf '== T915 CIワークフロー（静的検査）\n'
  check 'workflow ファイルがある' t_wf_file_exists
  check 'トリガーは pull_request（全ブランチ）と、main への push だけ' t_wf_triggers_are_pull_request_and_main_push_only
  check 'permissions は contents: read だけ' t_wf_permissions_are_contents_read_only
  check 'ジョブは ubuntu-24.04 で、timeout-minutes は15' t_wf_job_runs_on_ubuntu_2404_with_15_minute_limit
  check 'ステップの timeout は shellcheck 3、actionlint 2、gitleaks 2、unit 3、test-ci 10、smoke 8、contract 5' t_wf_step_timeouts_are_shellcheck3_actionlint2_gitleaks2_unit3_test_ci10_smoke8_contract5
  check 'ダミー認証情報は workflow の env だけに、値 test で書く' t_wf_dummy_credentials_are_workflow_env_only
  check 'concurrency は PR で ref、それ以外で SHA を使い、PR だけ取り消す' t_wf_concurrency_groups_pr_by_ref_and_pushes_by_sha
  check 'collect と stop は always、upload は failure で動く' t_wf_collect_always_upload_on_failure_stop_always
  check 'アーティファクトは固定の名前、e2e-logs/、保存7日' t_wf_uploads_logs_with_fixed_name_path_and_seven_day_retention
  check 'Secrets の文脈を読まない' t_wf_never_reads_secrets_context
  check 'run: に式と複数行の記法を書かない' t_wf_run_lines_have_no_expression_or_block_scalar
  check '式は concurrency と アーティファクト名の中だけ' t_wf_expressions_only_in_concurrency_and_artifact_name
  check 'uses は checkout と mise-action と upload-artifact の3つだけで、コミットSHAで固定する' t_wf_uses_checkout_mise_action_and_upload_artifact
  check 'checkout は認証情報を保存しない' t_wf_checkout_does_not_persist_credentials
  check 'ステップの順序は checkout、mise-action、shellcheck、actionlint、gitleaks、unit、test-ci、smoke、contract、collect、upload、stop' t_wf_steps_run_in_plan_order
  check '各ステップは計画どおりの入口を1つだけ呼ぶ' t_wf_each_step_runs_its_command
  check 'docker compose と docker-compose を呼ばない' t_wf_has_no_docker_compose_call
  check '品質ゲートは actionlint、gitleaks、yq を mise which で得て、3つの環境変数を付け、mise exec と || true を使わない' t_gate_runs_pinned_tools
  check '品質ゲートは、JSON の検査より前に jq の実体と版を確かめる' t_gate_checks_jq_first
  check 'JSON の値の取り出しは jq へ移し、json.load は mutate() の中だけに残す' t_json_extraction_uses_jq
  check 'swsc_count_api_requests は /api/ で始まる URL の件数だけを数える' t_count_api_requests_counts_only_api_urls
  check '.gitleaks.toml は useDefault、トップレベルの [allowlist]、stopwords を持たない' t_gitleaks_config_has_no_global_allowlist
  check 'gitleaks の段2の3規則は実行時に組み立てた値を検出し、値を出さない' t_gitleaks_rules_detect_runtime_built_values
  check 'gitleaks の段1の path 規則は FR-R0210 の11ファイルに当たり、対象外のパスには当たらない' t_gitleaks_path_rules_cover_eleven_files
  check 'gitleaks の段1の3規則の path は同じ文字列である' t_gitleaks_stage1_paths_are_identical
  check 'shellcheck の設定と mise.toml は必要な行だけを持つ（disable、[tasks]、[hooks]、[env] なし）' t_shellcheck_config_and_mise_toml_are_restricted
  check 'mise.toml は min_version と [tools] の6ツールだけを持つ（[tasks]、[hooks]、[env]、[plugins] なし）' t_mise_toml_is_restricted
  check 'test-ci の検査列に M08 の4シナリオが直列で入り、専用の step は増えない' t_ci_test_ci_scenarios
  check 'workflow は YAML として読め、形が一致する' t_wf_yaml_parses_with_expected_shape
  check '壊した定義の10件（permissions、timeout、always、SHA、Secrets、並び、trigger、persist、式、保持）は対応する検査が落ちる' t_wf_broken_definitions_fail
  check 'actionlint は式の誤りで失敗し、現在のワークフローでは成功する' t_actionlint_rejects_expression_error
  printf '== T916 文書（docs/ローカル実行とCI.md、README.md、AGENTS.md）\n'
  check '文書がある' t_doc_file_exists
  check '文書は # 見出しが1つで、先頭行にある' t_doc_has_one_h1_first
  check '文書に必須の節がある（実行方法から再現性、本番向けの検査、ゲートの結果まで）' t_doc_has_required_sections
  check '文書は3つの層、実行主体、品質ゲートの登録範囲を書く' t_doc_names_layers_executors_and_gate_scope
  check '文書はダミー認証情報の変数名だけを書き、値と設定の置き場所を書かない' t_doc_dummy_credentials_names_only
  check '文書の起動順は WireMock、管理API、pause、Squid の順である' t_doc_startup_order_is_wiremock_pause_squid
  check '文書の受信数は /api/ で始まるURLだけを数えると書く' t_doc_counts_api_urls_only
  check '文書の停止は docker rm -f で、SIGTERM の制約を書く' t_doc_stop_uses_rm_f_and_states_sigterm
  check '文書の所要時間は CI の初回実行の実測値と上限の根拠を書く' t_doc_duration_defers_to_ci
  check '文書のゲートの結果は G1 から G5 を含む' t_doc_gate_summary_covers_g1_to_g5
  check 'README は文書へのリンクと npm run の6操作を載せる' t_doc_readme_links_and_lists_npm_run
  check 'README に旧 Compose 手順が無く、docker-compose.yml も無い' t_doc_readme_has_no_old_compose_procedure
  check 'AGENTS.md の品質ゲート表に M09 の行があり、unit と smoke を登録し contract は登録しないと書く' t_doc_agents_row_registers_unit_smoke_not_contract
  check 'M07、M08、S14 が検査する README の行とリンクが残っている' t_doc_keeps_lines_checked_by_m07_m08_s14
  printf '== T917 品質ゲートへの登録\n'
  check 'ゲートに M09 のブロックがあり、閉じている' t_gate_m09_block_exists_and_is_closed
  check 'unit を smoke より前に、別の run で呼ぶ' t_gate_m09_block_registers_unit_then_smoke_as_separate_runs
  check '実行条件は M09 の対象と Squid、Client、WireMock、Dockerfile の変更' t_gate_m09_block_condition_covers_targets_and_squid_inputs
  check 'ブロックは統合テストの残存検査の後、結果の判定の前にある' t_gate_m09_block_placed_after_integration_check_and_before_summary
  check 'smoke の後に swsc- のコンテナの残存を確かめ、残れば status=1 にする' t_gate_m09_block_checks_leftover_containers_after_smoke
  check 'contract は登録せず、理由の NOTE 行がある' t_gate_does_not_register_contract_and_states_why
  check 'ブロックは AWS CLI と認証情報の変数を参照しない' t_gate_m09_block_has_no_aws_or_credentials
  check '既存の for ループに m09 を加えない' t_gate_m09_is_not_added_to_the_existing_loop
  check 'M02 はゲートの対象で、稼働中のスタックを前提とする NOTE が無い' t_gate_m02_runs_in_gate_without_stack_note
  check 'ゲートは Compose の呼び出しと、|| true で包んだ Docker の呼び出しを持たない' t_gate_no_compose_calls_or_or_true_wrapped_docker
  check 'ゲートは S14 の unit と管理対象の残存検査（swsc_check_managed_empty）を実行する' t_gate_runs_s14_contract_unit_and_managed_check_for_squid_block
  check 'ゲートの shellcheck は mise which の実体を、版を比べ、自動導入を止めて実行し、sh -n と mise exec を持たない' t_gate_runs_shellcheck_with_pinned_options
  check 'Docker の失敗は管理対象の残存検査で status=1 になる（ゲートの定義から取り出して確かめる）' t_managed_resource_check_failure
  check '管理対象の残存が無ければ、ゲートの残存検査は status=0 のまま' t_managed_resource_check_passes_when_empty_in_gate
  printf '== T2601 ロックとポート確認\n'
  check 'ロックは2回目の取得を1で拒否し、確認手順を示し、自動で消さない' t_lock_acquire_busy
  check '解放は所有者の自分だけ0で消し、他者の所有や不在では何も消さず1を返す' t_lock_release_non_owner
  check 'ポート確認は空きで0、使用中で1と番号を出し、不正な引数は1を返す' t_check_ports_free
  printf '== T2602 Client環境変数、件数、ログ\n'
  check '環境変数は不正な名前や制御文字を2で拒否し、正常な値は1要素ずつ docker へ渡し、出力と終了コードを保つ' t_client_once_env_rejects_control
  check 'WireMockの件数は完全一致だけを数え、食い違いや取得失敗は1を返し、経路を引数で渡す' t_wiremock_count_path
  check 'Squidログの検査は固定文字列で全一致を確かめ、不一致と取得失敗を区別して1を返す' t_squid_log_check
  printf '== T2603 管理対象の残存検査とラベル\n'
  check '残存検査は残りが無ければ0、接頭辞とラベルの両方が一致するものを名前付きで1にする' t_managed_empty_passes_when_nothing_is_left
  check '残存検査は残りの名前を標準エラーに示して1を返す' t_managed_empty_fails_and_names_labelled_prefixed_leftovers
  check '残存検査は片方だけ一致するものを数えない' t_managed_empty_ignores_label_only_and_prefix_only
  check '残存検査は docker の失敗を残存なしと区別して1を返す' t_managed_empty_docker_failure_is_not_reported_as_empty
  check 'runnerが作るネットワークは swsc-net で、管理ラベルを持つ' t_runner_labels_network_has_prefix_and_label
  printf '== T2603 入口のロックと trap（entry_trap_exit_143）\n'
  check 'startはロックが既にあれば何も起動せず1を返し、他者のロックを消さない' t_entry_trap_exit_143_start_refuses_when_locked
  check 'startは成功でも失敗でも終了後にロックが無い' t_entry_trap_exit_143_start_releases_lock_on_success_and_failure
  check 'startのTERMは stop の後にロックを解放し、終了コード143' t_entry_trap_exit_143_start_term_stops_then_releases_lock
  check 'startはポート使用中なら作成せず1を返し、ロックを解放する' t_entry_trap_exit_143_start_busy_port_creates_nothing_and_releases
  check 'test:ciはロックを1回だけ取り、stopの最中は保持し、終了後に無い' t_entry_trap_exit_143_test_ci_takes_lock_once_and_releases_after_stop
  check 'test:ciはロックが既にあれば何も起動せず1を返す' t_entry_trap_exit_143_test_ci_refuses_when_locked
  check 'test:ciのINTは130で、collectとstopの後にロックが無い' t_entry_trap_exit_143_test_ci_int_releases_after_stop
  check 'test:ciのTERMは143で、collectとstopの後にロックが無い' t_entry_trap_exit_143_test_ci_term_releases_after_stop
  check 'testのTERMは143で、stopの後にロックが無い' t_entry_trap_exit_143_test_op_term_releases_lock
  check 'testはロックが既にあれば何も起動せず1を返す' t_entry_trap_exit_143_test_op_refuses_when_locked
  check 'stop、clean、logsはロックが残っていても動き、ロックに触れない' t_entry_trap_exit_143_stop_clean_logs_ignore_lock
  check 'contractは4566使用中なら MiniStack を作らず aws を呼ばず1を返し、ロックを解放する' t_entry_trap_exit_143_contract_refuses_busy_4566_and_releases
  check 'contractはロックが既にあれば何も起動せず1を返す' t_entry_trap_exit_143_contract_refuses_when_locked
  check 'contractのTERMは143で、ロックが無い' t_entry_trap_exit_143_contract_term_releases_lock


}

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
