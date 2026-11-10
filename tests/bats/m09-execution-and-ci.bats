#!/usr/bin/env bats
# M09 の静的な検査（群1: t_wf_、t_gate_、t_mise_、t_gitleaks_、t_json_、t_bats_、t_run_bats_）。
# Docker と AWS CLI を使わず、ワークフロー、ゲート、設定ファイルの中身を確かめる。
# 旧の tests/m09-execution-and-ci.sh の check の名前を、そのまま @test の名前にした。
# 検査の本体は旧の入口の関数を字句のまま移した。入口の補助（must、rc_is、gate_has など）は、
# 入口を M09_LIB_ONLY=1 で読み込んで使う。
# shellcheck disable=SC2031,SC2034,SC2329 # 入口（tests/m09-execution-and-ci.sh）を . で読み込んで使う。WF などは入口が読み、関数は @test から呼ぶ。SWSC_JQ は setup が設定する。shellcheck は別ファイルを追えないため、これらを外す。

load 'helpers/common'

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  common_setup_tmp
  SELF=$ROOT/tests/m09-execution-and-ci.sh
  # 入口は $1 をモードとして読む。bats が渡す引数（検査の名前）を消してから読み込む。
  # 入口は読み込み時に TMP を空にする。bats が用意した作業場所を、読み込みの後で戻す。
  _tmp=$TMP
  set --
  # 入口の関数と変数だけを読む。M09_LIB_ONLY=1 のときは、本体（検査の実行）を走らせない。
  M09_LIB_ONLY=1
  M09_LIB_ROOT=$ROOT
  # shellcheck source=/dev/null
  . "$SELF"
  unset M09_LIB_ONLY M09_LIB_ROOT
  TMP=$_tmp
  # run_unit が用意する環境を、bats の setup でも用意する（jq の照合、ロックの作業場所）。
  # shellcheck source=/dev/null
  . "$ROOT/scripts/lib/resolve-tool.sh"
  resolve_tool jq 's/^jq-//p' --version || return 1
  jq_bin=$RESOLVED_PATH
  SWSC_JQ=$jq_bin
  export SWSC_JQ
  UNIT_LOCK_BASE=$(lock_case_dir) || return 1
  UNIT_LOCK=$UNIT_LOCK_BASE/ports.lock
  # 入口は set -eu で読み込まれる。bats の変数を守るため、-u を戻す。
  set +eu
}

teardown() {
  if [ -n "${UNIT_LOCK_BASE:-}" ]; then
    lock_case_clear "$UNIT_LOCK_BASE"
  fi
  common_teardown_tmp
}

# ---- 検査の本体（旧の入口の関数を字句のまま移した） ----

t_wf_file_exists() {
  [ -f "$WF" ] || return 1
  # YAML として読めることを yq で確かめる。読めなければ失敗する。
  _y=$(wf_yq_bin) || return 1
  "$_y" -e 'has("jobs")' "$WF" >/dev/null
}

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

t_bats_helpers_define_fakes_once() {
  for _fn in make_base_bin make_fake make_shims no_calls; do
    _hits=$(grep -rlE "^${_fn}\(\) \{" "$ROOT/tests" 2>/dev/null || true)
    [ "$_hits" = "$ROOT/tests/bats/helpers/fakes.bash" ] || return 1
  done
}

t_run_bats_entry_keeps_interface() {
  _r=$ROOT/tests/lib/run-bats.sh
  [ -f "$_r" ] || return 1
  must rc_is 2 sh "$_r"
  must rc_is 2 sh "$_r" bogus-mode
  # 第1引数に実在する .bats を渡し、第2引数の不正なモードだけを検査する（モードの検査の分岐を通すため）。
  must rc_is 2 sh "$_r" "$ROOT/tests/bats/s14-taskdef-contract.bats" bogus-mode
}

t_gate_checks_bats_first() {
  _gf=$ROOT/scripts/quality-gate.sh
  _bl=$(grep -n "^if ! resolve_tool bats 's/^Bats //p' --version; then" "$_gf" | head -1 | cut -d: -f1)
  _yq=$(grep -n '^if ! resolve_tool yq ' "$_gf" | head -1 | cut -d: -f1)
  [ -n "$_bl" ] && [ -n "$_yq" ] && [ "$_bl" -lt "$_yq" ]
}

t_gate_triggers_cover_bats_paths() {
  _gf=$ROOT/scripts/quality-gate.sh
  grep -Fq 'tests/bats/helpers/' "$_gf" && grep -Fq 'tests/lib/run-bats.sh' "$_gf" || return 1
  for _t in m02-routing-smoke m03-wiremock-scenarios m04-test-client m05-proxy-integration \
    m06-client-resilience m07-scenario-isolation m08-e2e-suite m09-execution-and-ci; do
    grep -Fq "tests/bats/${_t}.bats" "$_gf" || return 1
  done
}

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

t_gate_m02_runs_in_gate_without_stack_note() {
  _gf=$ROOT/scripts/quality-gate.sh
  must grep -Fxq "if has_match '^(Dockerfile|squid-config/|wiremock-scenarios/|test-client/|tests/|scripts/scenario-lib\.sh)'; then" "$_gf"
  must [ "$(grep -c 'NOTE: tests/m02-routing-smoke.sh' "$_gf" || true)" -eq 0 ]
  must grep -Fq 'tests/m02-routing-smoke.sh' "$_gf"
}

# ---- 検査（旧の check の名前と同じ。順序も旧と同じ） ----

# bats test_tags=unit
@test 'workflow ファイルがある' {
  t_wf_file_exists
}

# bats test_tags=unit
@test 'トリガーは pull_request（全ブランチ）と、main への push だけ' {
  t_wf_triggers_are_pull_request_and_main_push_only
}

# bats test_tags=unit
@test 'permissions は contents: read だけ' {
  t_wf_permissions_are_contents_read_only
}

# bats test_tags=unit
@test 'ジョブは ubuntu-24.04 で、timeout-minutes は15' {
  t_wf_job_runs_on_ubuntu_2404_with_15_minute_limit
}

# bats test_tags=unit
@test 'ステップの timeout は shellcheck 3、actionlint 2、gitleaks 2、unit 3、test-ci 10、smoke 8、contract 5' {
  t_wf_step_timeouts_are_shellcheck3_actionlint2_gitleaks2_unit3_test_ci10_smoke8_contract5
}

# bats test_tags=unit
@test 'ダミー認証情報は workflow の env だけに、値 test で書く' {
  t_wf_dummy_credentials_are_workflow_env_only
}

# bats test_tags=unit
@test 'concurrency は PR で ref、それ以外で SHA を使い、PR だけ取り消す' {
  t_wf_concurrency_groups_pr_by_ref_and_pushes_by_sha
}

# bats test_tags=unit
@test 'collect と stop は always、upload は failure で動く' {
  t_wf_collect_always_upload_on_failure_stop_always
}

# bats test_tags=unit
@test 'アーティファクトは固定の名前、e2e-logs/、保存7日' {
  t_wf_uploads_logs_with_fixed_name_path_and_seven_day_retention
}

# bats test_tags=unit
@test 'Secrets の文脈を読まない' {
  t_wf_never_reads_secrets_context
}

# bats test_tags=unit
@test 'run: に式と複数行の記法を書かない' {
  t_wf_run_lines_have_no_expression_or_block_scalar
}

# bats test_tags=unit
@test '式は concurrency と アーティファクト名の中だけ' {
  t_wf_expressions_only_in_concurrency_and_artifact_name
}

# bats test_tags=unit
@test 'uses は checkout と mise-action と upload-artifact の3つだけで、コミットSHAで固定する' {
  t_wf_uses_checkout_mise_action_and_upload_artifact
}

# bats test_tags=unit
@test 'checkout は認証情報を保存しない' {
  t_wf_checkout_does_not_persist_credentials
}

# bats test_tags=unit
@test 'ステップの順序は checkout、mise-action、shellcheck、actionlint、gitleaks、unit、test-ci、smoke、contract、collect、upload、stop' {
  t_wf_steps_run_in_plan_order
}

# bats test_tags=unit
@test '各ステップは計画どおりの入口を1つだけ呼ぶ' {
  t_wf_each_step_runs_its_command
}

# bats test_tags=unit
@test 'docker compose と docker-compose を呼ばない' {
  t_wf_has_no_docker_compose_call
}

# bats test_tags=unit
@test '品質ゲートは actionlint、gitleaks、yq を mise which で得て、3つの環境変数を付け、mise exec と || true を使わない' {
  t_gate_runs_pinned_tools
}

# bats test_tags=unit
@test '品質ゲートは、JSON の検査より前に jq の実体と版を確かめる' {
  t_gate_checks_jq_first
}

# bats test_tags=unit
@test 'JSON の値の取り出しは jq へ移し、json.load は mutate() の中だけに残す' {
  t_json_extraction_uses_jq
}

# bats test_tags=unit
@test 'bats の偽の用意（4つの関数）は tests/bats/helpers/fakes.bash の1か所だけ' {
  t_bats_helpers_define_fakes_once
}

# bats test_tags=unit
@test 'run-bats.sh は引数の数とモードを検査し、不正なら終了コード2' {
  t_run_bats_entry_keeps_interface
}

# bats test_tags=unit
@test '品質ゲートは bats の実体と版を、yq より前に確かめる' {
  t_gate_checks_bats_first
}

# bats test_tags=unit
@test 'M02〜M09 の実行条件は tests/bats の変更でも対応するテストを走らせる' {
  t_gate_triggers_cover_bats_paths
}

# bats test_tags=unit
@test '.gitleaks.toml は useDefault、トップレベルの [allowlist]、stopwords を持たない' {
  t_gitleaks_config_has_no_global_allowlist
}

# bats test_tags=unit
@test 'gitleaks の段2の3規則は実行時に組み立てた値を検出し、値を出さない' {
  t_gitleaks_rules_detect_runtime_built_values
}

# bats test_tags=unit
@test 'gitleaks の段1の path 規則は FR-R0210 の11ファイルに当たり、対象外のパスには当たらない' {
  t_gitleaks_path_rules_cover_eleven_files
}

# bats test_tags=unit
@test 'gitleaks の段1の3規則の path は同じ文字列である' {
  t_gitleaks_stage1_paths_are_identical
}

# bats test_tags=unit
@test 'mise.toml は min_version と [tools] の6ツールだけを持つ（[tasks]、[hooks]、[env]、[plugins] なし）' {
  t_mise_toml_is_restricted
}

# bats test_tags=unit
@test 'workflow は YAML として読め、形が一致する' {
  t_wf_yaml_parses_with_expected_shape
}

# bats test_tags=unit
@test '壊した定義の10件（permissions、timeout、always、SHA、Secrets、並び、trigger、persist、式、保持）は対応する検査が落ちる' {
  t_wf_broken_definitions_fail
}

# bats test_tags=unit
@test 'ゲートに M09 のブロックがあり、閉じている' {
  t_gate_m09_block_exists_and_is_closed
}

# bats test_tags=unit
@test 'unit を smoke より前に、別の run で呼ぶ' {
  t_gate_m09_block_registers_unit_then_smoke_as_separate_runs
}

# bats test_tags=unit
@test '実行条件は M09 の対象と Squid、Client、WireMock、Dockerfile の変更' {
  t_gate_m09_block_condition_covers_targets_and_squid_inputs
}

# bats test_tags=unit
@test 'ブロックは統合テストの残存検査の後、結果の判定の前にある' {
  t_gate_m09_block_placed_after_integration_check_and_before_summary
}

# bats test_tags=unit
@test 'smoke の後に swsc- のコンテナの残存を確かめ、残れば status=1 にする' {
  t_gate_m09_block_checks_leftover_containers_after_smoke
}

# bats test_tags=unit
@test 'contract は登録せず、理由の NOTE 行がある' {
  t_gate_does_not_register_contract_and_states_why
}

# bats test_tags=unit
@test 'ブロックは AWS CLI と認証情報の変数を参照しない' {
  t_gate_m09_block_has_no_aws_or_credentials
}

# bats test_tags=unit
@test '既存の for ループに m09 を加えない' {
  t_gate_m09_is_not_added_to_the_existing_loop
}

# bats test_tags=unit
@test 'M02 はゲートの対象で、稼働中のスタックを前提とする NOTE が無い' {
  t_gate_m02_runs_in_gate_without_stack_note
}

# bats test_tags=unit
@test 'ゲートは Compose の呼び出しと、|| true で包んだ Docker の呼び出しを持たない' {
  t_gate_no_compose_calls_or_or_true_wrapped_docker
}

# bats test_tags=unit
@test 'ゲートは S14 の unit と管理対象の残存検査（swsc_check_managed_empty）を実行する' {
  t_gate_runs_s14_contract_unit_and_managed_check_for_squid_block
}

# bats test_tags=unit
@test 'ゲートの shellcheck は mise which の実体を、版を比べ、自動導入を止めて実行し、sh -n と mise exec を持たない' {
  t_gate_runs_shellcheck_with_pinned_options
}

# ---- 群2（文書と CI の検査）。関数の本体は旧の入口から字句のまま移した ----

t_ci_test_ci_scenarios() {
  _y=$(wf_yq_bin) || return 1
  # 既存の test:ci が先、4シナリオの test:ci が後。失敗したら後は動かない（&&）。
  "$_y" -e '.jobs.e2e.steps[] | select(.name == "test-ci") | .run == "npm run test:ci && sh scripts/e2e.sh test:ci normal error-500-then-200 ratelimit-429 slow-5000"' "$WF" >/dev/null || return 1
  # 専用の step を増やしていないこと。名前付きの step は計画どおり9件（checkout と upload は uses で数えない）。
  "$_y" -e '([.jobs.e2e.steps[] | select(has("name"))] | length) == 9' "$WF" >/dev/null || return 1
  # job 名と required status check の名前（e2e、既存の step 名 smoke と contract）は変わらない。
  "$_y" -e '(.jobs | has("e2e")) and ([.jobs.e2e.steps[] | select(.name == "smoke" or .name == "contract")] | length) == 2' "$WF" >/dev/null
}

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

# ---- 群2 の検査（旧の check の名前と同じ。順序も旧と同じ） ----

# bats test_tags=unit
@test 'test-ci の検査列に M08 の4シナリオが直列で入り、専用の step は増えない' {
  t_ci_test_ci_scenarios
}

# bats test_tags=unit
@test '文書がある' {
  t_doc_file_exists
}

# bats test_tags=unit
@test '文書は # 見出しが1つで、先頭行にある' {
  t_doc_has_one_h1_first
}

# bats test_tags=unit
@test '文書に必須の節がある（実行方法から再現性、本番向けの検査、ゲートの結果まで）' {
  t_doc_has_required_sections
}

# bats test_tags=unit
@test '文書は3つの層、実行主体、品質ゲートの登録範囲を書く' {
  t_doc_names_layers_executors_and_gate_scope
}

# bats test_tags=unit
@test '文書はダミー認証情報の変数名だけを書き、値と設定の置き場所を書かない' {
  t_doc_dummy_credentials_names_only
}

# bats test_tags=unit
@test '文書の起動順は WireMock、管理API、pause、Squid の順である' {
  t_doc_startup_order_is_wiremock_pause_squid
}

# bats test_tags=unit
@test '文書の受信数は /api/ で始まるURLだけを数えると書く' {
  t_doc_counts_api_urls_only
}

# bats test_tags=unit
@test '文書の停止は docker rm -f で、SIGTERM の制約を書く' {
  t_doc_stop_uses_rm_f_and_states_sigterm
}

# bats test_tags=unit
@test '文書の所要時間は CI の初回実行の実測値と上限の根拠を書く' {
  t_doc_duration_defers_to_ci
}

# bats test_tags=unit
@test '文書のゲートの結果は G1 から G5 を含む' {
  t_doc_gate_summary_covers_g1_to_g5
}

# bats test_tags=unit
@test 'README は文書へのリンクと npm run の6操作を載せる' {
  t_doc_readme_links_and_lists_npm_run
}

# bats test_tags=unit
@test 'README に旧 Compose 手順が無く、docker-compose.yml も無い' {
  t_doc_readme_has_no_old_compose_procedure
}

# bats test_tags=unit
@test 'AGENTS.md の品質ゲート表に M09 の行があり、unit と smoke を登録し contract は登録しないと書く' {
  t_doc_agents_row_registers_unit_smoke_not_contract
}

# bats test_tags=unit
@test 'M07、M08、S14 が検査する README の行とリンクが残っている' {
  t_doc_keeps_lines_checked_by_m07_m08_s14
}

# ---- 信号以外の検査 第1区切り（信号以外の unit の検査）。関数の本体は旧の入口から字句のまま移した ----

t_usage_rejects_bad_arguments() {
  must rc_is 2 sh "$ROOT/tests/m09-execution-and-ci.sh" bogus
  must rc_is 2 sh "$ROOT/tests/m09-execution-and-ci.sh" unit extra
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

t_only_swsc_aws_calls_aws() {
  # 「aws」をコマンドとして呼ぶ行は、scripts/e2e*.sh の中で1行だけでなければならない（swsc_aws）。
  _n=$(grep -hE '(^|[;&|(])[[:space:]]*(env [^;]*)?aws[[:space:]]' "$ROOT"/scripts/e2e*.sh |
    grep -vc '^[[:space:]]*#' || true)
  must [ "$_n" -eq 1 ]
  must grep -q 'swsc_aws()' "$ROOT/scripts/e2e-lib.sh"
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

t_shell_syntax_and_python_compile_pass() {
  for _f in scripts/e2e.sh scripts/e2e-lib.sh scripts/e2e-contract.sh scripts/e2e-runner.sh ecs/squid/derive-config.sh ecs/squid/entrypoint.sh tests/m09-execution-and-ci.sh; do
    must sh -n "$ROOT/$_f"
  done
  must env PYTHONPYCACHEPREFIX="$TMP/pyc" python3 -B -m py_compile "$ROOT/scripts/e2e-taskdef.py"
}

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

t_docker_args_keeps_env_values_out_of_args_and_private_file() {
  runner_setup || return 1
  runner_docker_args "$TMP/taskdef.json" "$TMP/run" || return 1
  must grep -qxF 'HTTP_PROXY=http://127.0.0.1:3128' "$TMP/run/swsc-client-4242.env"
  must [ -z "$(grep -F 'http://127.0.0.1:3128' "$TMP/run/swsc-client-4242.args" || true)" ]
  must [ "$(python3 -B -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$TMP/run/swsc-client-4242.env")" = '0o600' ]
}

t_docker_args_rejects_newline_in_value() {
  runner_setup || return 1
  runner_mutate "d['containerDefinitions'][0]['environment'][0]['value'] = 'a\\nb'" || return 1
  _r=0
  runner_docker_args "$TMP/bad.json" "$TMP/run" >/dev/null 2>&1 || _r=$?
  must [ "$_r" -eq 1 ]
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

t_stop_clean_collect_start_test_never_call_aws() {
  entry_setup || return 1
  for _op in start test stop clean collect test:ci; do
    entry_run "$_op" >/dev/null 2>&1 || true
  done
  must [ ! -s "$TMP/rec-aws" ]
}

t_all_operations_never_call_docker_compose() {
  entry_setup || return 1
  for _op in start test logs stop clean test:ci collect contract; do
    entry_run "$_op" >/dev/null 2>&1 || true
  done
  must [ -z "$(grep -h 'docker-compose' "$TMP/seq.log" 2>/dev/null || true)" ]
}

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

t_test_stops_without_client_when_squid_not_running() {
  entry_setup || return 1
  printf false >"$TMP/running-out"
  _rc=0
  entry_run test >/dev/null 2>"$TMP/err" || _rc=$?
  must [ "$_rc" -ne 0 ]
  if grep -q 'swsc-client' "$TMP/seq.log" 2>/dev/null; then return 1; fi
}

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

t_collect_does_not_treat_uuid_tail_as_account() {
  entry_setup || return 1
  _acct=$(printf '%s' 1 2 3 4 5 6 7 8 9 0 1 2)
  printf 'request 9f1c2d3e-4a5b-6c7d-8e9f-%s\n' "$_acct" >"$TMP/logs-out"
  _rc=0
  entry_run collect >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 0 ]
  must grep -q "9f1c2d3e-4a5b-6c7d-8e9f-$_acct" "$TMP/logs/containers/swsc-squid.log"
}

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

t_client_once_passes_base_url_unchanged() {
  entry_setup || return 1
  mkdir -p "$TMP/e2e/run"
  printf -- '--name\nswsc-client-4242\n--label\nswsc.managed=true\n--env-file\n/x/swsc-client-4242.env\nswsc-client:e2e\n' \
    >"$TMP/e2e/run/swsc-client-4242.args"
  lib_call "swsc_client_once $TMP/e2e/run 4242 http://api.example.com" >/dev/null 2>&1 || true
  must grep -q 'TEST_API_BASE_URL=http://api.example.com' "$TMP/rec-docker"
  if grep -q 'TEST_API_BASE_URL=--' "$TMP/rec-docker"; then return 1; fi
}

t_wiremock_reset_uses_delete_requests() {
  entry_setup || return 1
  _rc=0
  lib_call 'swsc_wiremock_reset' >/dev/null 2>&1 || _rc=$?
  must grep -q -e '-X DELETE .*/__admin/requests' "$TMP/rec-curl"
  if grep -q 'requests/reset' "$TMP/rec-curl"; then return 1; fi
}

t_smoke_registers_items_1_to_11_in_order() {
  _seq=$(grep -E '^  smoke_item [0-9]+ ' "$ROOT/tests/m09-execution-and-ci.sh" | awk '{print $2}' | tr '\n' ' ')
  [ "$_seq" = '1 2 3 4 5 6 7 8 9 10 11 ' ]
}

t_contract_registers_c1_to_c6_in_order() {
  _seq=$(grep -E '^  contract_item C[0-9] ' "$ROOT/tests/m09-execution-and-ci.sh" | awk '{print $2}' | tr '\n' ' ')
  [ "$_seq" = 'C1 C2 C3 C4 C5 C6 ' ]
}

t_smoke_runs_unit_before_docker() {
  _f=$ROOT/tests/m09-execution-and-ci.sh
  # shellcheck disable=SC2016 # grep の検索語。検査ファイル内の行をそのまま探すため、$ROOT と引用符を展開させない。
  _u=$(grep -n '^  if ! sh "$ROOT/tests/m09-execution-and-ci.sh" unit' "$_f" | head -n 1 | cut -d: -f1)
  _d=$(grep -n '^  # Why: swsc- の残りを消してから' "$_f" | head -n 1 | cut -d: -f1)
  [ -n "$_u" ] && [ -n "$_d" ] && [ "$_u" -lt "$_d" ]
}

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

t_count_api_requests_counts_only_api_urls() {
  printf '%s' '{"requests":[{"request":{"url":"/api/a"}},{"request":{"url":"/squid-internal-periodic/x"}},{"request":{"url":"/api/b"}}]}' \
    > "$TMP/requests.json"
  SWSC_ROOT=$ROOT
  _n=$(. "$ROOT/scripts/e2e-lib.sh"; swsc_count_api_requests < "$TMP/requests.json") || return 1
  must [ "$_n" = 2 ]
}

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

# ---- 信号以外の検査 第1区切り の検査（旧の check の名前と同じ。順序も旧と同じ） ----

# bats test_tags=unit
@test '不正なモードと余計な引数は終了コード2' {
  t_usage_rejects_bad_arguments
}

# bats test_tags=unit
@test '.gitignoreに.e2e/とe2e-logs/がある' {
  t_gitignore_hides_run_outputs
}

# bats test_tags=unit
@test '操作なしは終了コード2' {
  t_entry_without_operation_exits_2
}

# bats test_tags=unit
@test '未知の操作は終了コード2' {
  t_entry_unknown_operation_exits_2
}

# bats test_tags=unit
@test 'logsは追加の引数を受けても引数誤りにならない' {
  t_logs_accepts_extra_arguments
}

# bats test_tags=unit
@test 'startはdockerが無いと原因を示して止まる' {
  t_start_without_docker_names_docker
}

# bats test_tags=unit
@test 'awsを呼ぶ行はswsc_awsの1か所だけ' {
  t_only_swsc_aws_calls_aws
}

# bats test_tags=unit
@test 'FR-920の検出がコマンドの形を捕まえる' {
  t_fr920_detector_catches_command_forms
}

# bats test_tags=unit
@test 'FR-920の検出がコメントと語を誤検出しない' {
  t_fr920_detector_allows_comments_and_words
}

# bats test_tags=unit
@test 'M09の対象ファイルにdocker-composeの呼び出しが無い' {
  t_fr920_holds_for_m09_files
}

# bats test_tags=unit
@test '前提検査にポートの確認を含めない' {
  t_prereq_for_smoke_has_no_port_check
}

# bats test_tags=unit
@test '同じ入力から同じバイト列になる' {
  t_render_is_byte_identical_for_same_input
}

# bats test_tags=unit
@test '未知のプレースホルダーは名前を示して失敗する' {
  t_render_fails_on_unknown_placeholder_and_names_it
}

# bats test_tags=unit
@test '置換されずに残った形式（小文字）は失敗する' {
  t_render_fails_on_leftover_placeholder_in_key_or_value
}

# bats test_tags=unit
@test '許可リスト外の項目（volumes）は名指しで失敗する' {
  t_render_rejects_disallowed_key_by_name
}

# bats test_tags=unit
@test 'dependsOnの条件はSTARTかHEALTHYだけ' {
  t_render_rejects_dependency_condition_other_than_start_or_healthy
}

# bats test_tags=unit
@test 'healthCheckのCMD-SHELL以外は失敗する' {
  t_render_rejects_health_check_that_is_not_cmd_shell
}

# bats test_tags=unit
@test '値の文字種違反は値を出さずに失敗する' {
  t_render_rejects_malformed_values_without_printing_them
}

# bats test_tags=unit
@test 'テンプレートにmockの既定値とロールARNが無い' {
  t_template_names_no_mock_default_or_role_arn
}

# bats test_tags=unit
@test '完成版の生成はswsc_renderの1か所に集まる' {
  t_swsc_render_is_the_only_generation_path
}

# bats test_tags=unit
@test 'swsc_render経由の出力は直接の生成と一致する' {
  t_swsc_render_matches_direct_render
}

# bats test_tags=unit
@test '層1: テンプレートにmockの既定値とSQUID_MOCK_が無い' {
  t_template_layer1_has_no_mock_default
}

# bats test_tags=unit
@test '本番向けはdirectで生成でき、検査に通る' {
  t_production_render_with_direct_passes_check
}

# bats test_tags=unit
@test '本番向けはdirect以外の上流を拒否する（大文字、空白、空を含む）' {
  t_production_render_rejects_upstream_other_than_direct
}

# bats test_tags=unit
@test '本番向けはWireMockの宛先の指定を拒否する' {
  t_production_render_rejects_mock_destination
}

# bats test_tags=unit
@test 'check-productionは上流の各種の誤りを拒否し、値を出さない' {
  t_check_production_rejects_each_upstream_variant
}

# bats test_tags=unit
@test 'check-productionはSQUID_UPSTREAMの欠落を拒否する' {
  t_check_production_rejects_missing_upstream
}

# bats test_tags=unit
@test 'check-productionはSQUID_MOCK_の残存を拒否する' {
  t_check_production_rejects_leftover_mock_destination
}

# bats test_tags=unit
@test 'check-productionは読めない入力で終了コード2' {
  t_check_production_exit_2_when_unreadable
}

# bats test_tags=unit
@test '入口のcheck-productionの終了コードが検査の結果と一致する' {
  t_entry_check_production_exit_codes
}

# bats test_tags=unit
@test '派生: 未設定を拒否する' {
  t_derive_rejects_unset_upstream
}

# bats test_tags=unit
@test '派生: 上流の値の変形（大文字、空白、空）を拒否する' {
  t_derive_rejects_upstream_variants
}

# bats test_tags=unit
@test '派生: mockは宛先の1行だけを変える' {
  t_derive_mock_rewrites_only_the_peer_line
}

# bats test_tags=unit
@test '派生: directはピアの行を除き always_direct を足す' {
  t_derive_direct_removes_peer_lines_and_adds_always_direct
}

# bats test_tags=unit
@test '派生: directはSQUID_MOCK_を無視する' {
  t_derive_direct_ignores_mock_destination
}

# bats test_tags=unit
@test '派生: 宛先ホストへの注入になる値を拒否する' {
  t_derive_mock_rejects_host_injection
}

# bats test_tags=unit
@test '派生: 宛先ポートの範囲外と非数字を拒否する' {
  t_derive_mock_rejects_bad_port
}

# bats test_tags=unit
@test '派生: 宛先ポートの境界値（1、9999、10000、65535）を受理する' {
  t_derive_mock_accepts_port_boundaries
}

# bats test_tags=unit
@test '派生: 派生元の必須の行が欠けたら失敗する' {
  t_derive_rejects_source_without_each_required_line
}

# bats test_tags=unit
@test '派生: 派生元の必須の行が重複したら失敗する' {
  t_derive_rejects_duplicated_required_line
}

# bats test_tags=unit
@test 'Dockerfile: ubuntu/squid:latest から作り、名前を揃える' {
  t_dockerfile_builds_from_ubuntu_squid_latest
}

# bats test_tags=unit
@test 'エントリポイント: 派生、parse、表示、exec の順' {
  t_entrypoint_orders_derive_parse_report_exec
}

# bats test_tags=unit
@test 'エントリポイント: directで parse の後に元のエントリポイントへ渡す' {
  t_entrypoint_direct_runs_parse_then_hands_over
}

# bats test_tags=unit
@test 'エントリポイント: 上流が不正なら squid を呼ばずに止まる' {
  t_entrypoint_stops_before_squid_when_upstream_invalid
}

# bats test_tags=unit
@test 'ビルド文脈は元の設定と一致し、5ファイルだけ' {
  t_squid_context_is_a_byte_copy_of_sources
}

# bats test_tags=unit
@test 'シェルの構文とPythonの構文が通る' {
  t_shell_syntax_and_python_compile_pass
}

# bats test_tags=unit
@test 'swsc_awsはダミー認証情報が無い、またはtest以外なら呼ばずに止まる' {
  t_swsc_aws_refuses_missing_or_non_dummy_credentials
}

# bats test_tags=unit
@test 'swsc_awsは接続先と地域を明示し、設定元を外し、時間制限を付ける' {
  t_swsc_aws_passes_endpoint_region_and_clears_config_sources
}

# bats test_tags=unit
@test 'ポート確認は、接続できないポートを空きと判定する' {
  t_port_check_reports_closed_port_as_free
}

# bats test_tags=unit
@test '識別情報のマスクは12桁とARNを消し、16進の値は残す' {
  t_mask_masks_account_and_arn_and_keeps_hex_hash
}

# bats test_tags=unit
@test '比較は順序差と空の既定値を一致とみなす' {
  t_compare_accepts_reordered_env_and_empty_defaults
}

# bats test_tags=unit
@test '比較はイメージの変更を不一致にする' {
  t_compare_fails_on_image_change
}

# bats test_tags=unit
@test '比較は環境変数の値の変更を不一致にし、値を出さない' {
  t_compare_fails_on_environment_value_and_does_not_print_it
}

# bats test_tags=unit
@test '比較はessentialの変更を不一致にする' {
  t_compare_fails_on_essential_change
}

# bats test_tags=unit
@test '比較はポートの変更を不一致にする' {
  t_compare_fails_on_port_change
}

# bats test_tags=unit
@test '比較はdependsOnの変更を不一致にする' {
  t_compare_fails_on_depends_on_change
}

# bats test_tags=unit
@test '比較はhealthCheckの変更を不一致にする' {
  t_compare_fails_on_health_check_change
}

# bats test_tags=unit
@test '比較はコンテナ数の変更を不一致にする' {
  t_compare_fails_on_container_count_change
}

# bats test_tags=unit
@test '比較はnetworkModeの変更を不一致にする' {
  t_compare_fails_on_network_mode_change
}

# bats test_tags=unit
@test 'C4は、EXPOSEだけで公開していないポート（null）を数えない' {
  t_contract_c4_accepts_exposed_but_unpublished_ports
}

# bats test_tags=unit
@test 'C4は、2つ目の公開ポート、127.0.0.1以外の公開、ソケット、公開なしを拒否する' {
  t_contract_c4_rejects_a_second_published_port_a_wider_bind_and_the_socket
}

# bats test_tags=unit
@test 'docker-argsは各コンテナの引数、.env、依存を書く' {
  t_docker_args_writes_args_and_env_for_each_container
}

# bats test_tags=unit
@test 'docker-argsは先頭が - の image を拒否する' {
  t_docker_args_rejects_image_that_starts_with_dash
}

# bats test_tags=unit
@test 'docker-argsは後ろのコンテナに制御文字があれば、何も書かない' {
  t_docker_args_writes_nothing_when_a_later_container_has_a_control_character
}

# bats test_tags=unit
@test 'WireMockの待機は、コンテナが止まっていれば上限を待たずに止まる' {
  t_runner_wait_wiremock_fails_fast_when_the_container_stopped
}

# bats test_tags=unit
@test 'healthyの待機は、コンテナが止まっていれば上限を待たずに止まる' {
  t_runner_wait_healthy_fails_fast_when_the_container_stopped
}

# bats test_tags=unit
@test 'Squidの待受の確認は、コンテナが止まっていれば上限を待たずに止まる' {
  t_runner_probe_squid_fails_fast_when_the_container_stopped
}

# bats test_tags=unit
@test '環境変数の値は引数に出ず、.env は0600' {
  t_docker_args_keeps_env_values_out_of_args_and_private_file
}

# bats test_tags=unit
@test '改行を含む値は失敗する' {
  t_docker_args_rejects_newline_in_value
}

# bats test_tags=unit
@test '変換の対象外（COMPLETE、CMD、ポート重複、bridge）は失敗する' {
  t_docker_args_rejects_items_outside_the_conversion
}

# bats test_tags=unit
@test 'ヘルスチェックをdockerのオプションへ変換する' {
  t_docker_args_translates_health_check_to_docker_options
}

# bats test_tags=unit
@test '名前とラベルを持ち、特権、ソケット、公開を持たない' {
  t_docker_args_names_labels_and_forbids_host_privileges
}

# bats test_tags=unit
@test '起動順はWireMock、管理APIの応答、pause、Squid' {
  t_runner_start_orders_wiremock_admin_check_pause_squid
}

# bats test_tags=unit
@test 'WireMockが応答しなければpauseとSquidを作らない' {
  t_runner_creates_no_pause_or_squid_when_wiremock_never_ready
}

# bats test_tags=unit
@test 'Squidはhealthyの後に、pauseの名前空間から待受を確かめる' {
  t_runner_waits_for_squid_health_before_probing
}

# bats test_tags=unit
@test '作るコンテナは全てswsc-の名前とラベルを持つ' {
  t_runner_every_created_container_has_prefix_and_label
}

# bats test_tags=unit
@test 'Clientはpauseの名前空間に参加し、終了コードを返す' {
  t_runner_client_joins_pause_namespace_and_returns_its_exit_code
}

# bats test_tags=unit
@test '後始末は接頭辞とラベルの両方が一致するものだけを消し、Squidを先に消す' {
  t_runner_remove_managed_removes_only_prefixed_labelled_containers_in_order
}

# bats test_tags=unit
@test 'WireMockの受信数は /api/ で始まるURLだけを数える' {
  t_wiremock_total_counts_only_api_urls
}

# bats test_tags=unit
@test '起動の前提は aws と認証情報を要求しない（前提不足を出さず、awsを呼ばない）' {
  t_start_prereq_skips_aws_and_credentials
}

# bats test_tags=unit
@test 'testとtest:ciの前提は aws と認証情報を要求しない' {
  t_test_and_test_ci_prereq_skip_aws_and_credentials
}

# bats test_tags=unit
@test 'start、test、stop、clean、collect、test:ci は aws を呼ばない' {
  t_stop_clean_collect_start_test_never_call_aws
}

# bats test_tags=unit
@test '全操作で docker-compose を呼ばない' {
  t_all_operations_never_call_docker_compose
}

# bats test_tags=unit
@test 'start_mainはtrapを持たない' {
  t_start_main_has_no_trap
}

# bats test_tags=unit
@test 'stopは冪等で、接頭辞とラベルの両方が一致するものだけ消す' {
  t_stop_is_idempotent_and_removes_only_prefixed_labelled
}

# bats test_tags=unit
@test 'cleanは自分のイメージ2つと一時物だけを消す' {
  t_clean_removes_only_own_images_and_dirs
}

# bats test_tags=unit
@test 'cleanは目印の無いディレクトリを消さずに失敗する' {
  t_clean_refuses_directories_without_the_marker
}

# bats test_tags=unit
@test 'cleanは片方が拒否されても、目印のあるもう片方は消す' {
  t_clean_still_removes_the_marked_directory_when_the_other_is_refused
}

# bats test_tags=unit
@test 'cleanはシンボリックリンクの出力先を辿らない' {
  t_clean_does_not_follow_a_symlink_output_dir
}

# bats test_tags=unit
@test 'collectは目印の無いログ先に触れずに失敗する' {
  t_collect_refuses_a_foreign_log_dir_and_leaves_it_untouched
}

# bats test_tags=unit
@test 'collectは新しいログ先に目印を置き、再実行できる' {
  t_collect_marks_a_new_log_dir_and_reuses_it
}

# bats test_tags=unit
@test '出力先の用意は、空、/、相対パス、シンボリックリンクを拒否する' {
  t_prepare_dir_rejects_empty_root_relative_and_symlink
}

# bats test_tags=unit
@test '出力先の用意は、無いディレクトリと空のディレクトリを受け入れる' {
  t_prepare_dir_accepts_missing_and_empty_directories
}

# bats test_tags=unit
@test 'startは目印の無い出力先を、ビルドの前に拒否する' {
  t_start_refuses_a_foreign_e2e_dir_before_building
}

# bats test_tags=unit
@test 'logsは名前を swsc- に写し、未知の名前を終了コード2にする' {
  t_logs_maps_name_to_prefixed_container_and_rejects_unknown
}

# bats test_tags=unit
@test 'testはSquidが稼働していなければClientを起動せず止まる' {
  t_test_stops_without_client_when_squid_not_running
}

# bats test_tags=unit
@test 'collectは対象が無くても0で、missing.txtに名前を残す' {
  t_collect_without_containers_exits_0_and_records_missing
}

# bats test_tags=unit
@test 'collectはコンテナのログ、Squidのログ、完成版を集める' {
  t_collect_gathers_container_logs_squid_logs_and_files
}

# bats test_tags=unit
@test 'collectは冪等で、元が無い回は既存の収集物を消さない' {
  t_collect_is_idempotent_and_keeps_existing_when_source_missing
}

# bats test_tags=unit
@test 'collectはARNと12桁のアカウントIDをコピーの上でマスクする' {
  t_collect_masks_arn_and_account_in_copies
}

# bats test_tags=unit
@test 'collectはUUIDの末尾の12桁を識別情報として扱わない' {
  t_collect_does_not_treat_uuid_tail_as_account
}

# bats test_tags=unit
@test 'collectはマスクで消せないファイルを削除し、scrub.txtに記録する。2回目は0' {
  t_collect_removes_unmaskable_records_scrub_and_second_run_is_0
}

# bats test_tags=unit
@test 'testは出力をログのファイルへ残す' {
  t_test_run_writes_output_to_log_files
}

# bats test_tags=unit
@test '検査の1件は、ステータスと受信数の両方が期待どおりなら合格' {
  t_test_item_compares_status_and_wiremock_count
}

# bats test_tags=unit
@test 'Clientのベースurlは引数の組み立ての影響を受けずに docker run へ届く' {
  t_client_once_passes_base_url_unchanged
}

# bats test_tags=unit
@test 'WireMockの受信記録の消去は DELETE /__admin/requests を使う' {
  t_wiremock_reset_uses_delete_requests
}

# bats test_tags=unit
@test 'smokeの項目は表のとおり1から11の順に登録されている' {
  t_smoke_registers_items_1_to_11_in_order
}

# bats test_tags=unit
@test 'contractの項目は表のとおりC1からC6の順に登録されている' {
  t_contract_registers_c1_to_c6_in_order
}

# bats test_tags=unit
@test 'smokeはunitを、Dockerを呼ぶ前に実行する' {
  t_smoke_runs_unit_before_docker
}

# bats test_tags=unit
@test 'contractは認証情報が無いと、unit、Docker、AWS CLIを呼ばずに止まる' {
  t_contract_precheck_stops_before_unit_docker_aws
}

# bats test_tags=unit
@test 'swsc_count_api_requests は /api/ で始まる URL の件数だけを数える' {
  t_count_api_requests_counts_only_api_urls
}

# bats test_tags=unit
@test 'shellcheck の設定と mise.toml は必要な行だけを持つ（disable、[tasks]、[hooks]、[env] なし）' {
  t_shellcheck_config_and_mise_toml_are_restricted
}

# bats test_tags=unit
@test 'ロックは2回目の取得を1で拒否し、確認手順を示し、自動で消さない' {
  t_lock_acquire_busy
}

# bats test_tags=unit
@test '解放は所有者の自分だけ0で消し、他者の所有や不在では何も消さず1を返す' {
  t_lock_release_non_owner
}

# bats test_tags=unit
@test 'ポート確認は空きで0、使用中で1と番号を出し、不正な引数は1を返す' {
  t_check_ports_free
}

# bats test_tags=unit
@test '環境変数は不正な名前や制御文字を2で拒否し、正常な値は1要素ずつ docker へ渡し、出力と終了コードを保つ' {
  t_client_once_env_rejects_control
}

# bats test_tags=unit
@test 'WireMockの件数は完全一致だけを数え、食い違いや取得失敗は1を返し、経路を引数で渡す' {
  t_wiremock_count_path
}

# bats test_tags=unit
@test 'Squidログの検査は固定文字列で全一致を確かめ、不一致と取得失敗を区別して1を返す' {
  t_squid_log_check
}

# bats test_tags=unit
@test '残存検査は残りが無ければ0、接頭辞とラベルの両方が一致するものを名前付きで1にする' {
  t_managed_empty_passes_when_nothing_is_left
}

# bats test_tags=unit
@test '残存検査は残りの名前を標準エラーに示して1を返す' {
  t_managed_empty_fails_and_names_labelled_prefixed_leftovers
}

# bats test_tags=unit
@test '残存検査は片方だけ一致するものを数えない' {
  t_managed_empty_ignores_label_only_and_prefix_only
}

# bats test_tags=unit
@test '残存検査は docker の失敗を残存なしと区別して1を返す' {
  t_managed_empty_docker_failure_is_not_reported_as_empty
}

# bats test_tags=unit
@test 'runnerが作るネットワークは swsc-net で、管理ラベルを持つ' {
  t_runner_labels_network_has_prefix_and_label
}

# ---- 信号以外の検査 第2区切り（信号以外の unit の検査）。関数の本体は旧の入口から字句のまま移した ----

t_package_json_delegates_six_scripts() {
  # shellcheck disable=SC2016 # 単一引用符の中の $s、$k は jq の変数であり、シェルで展開させない。
  must "$jq_bin" -e '
    .scripts as $s
    | (["start", "test", "logs", "stop", "clean", "test:ci"]
        | all(. as $k | $s[$k] == ("sh scripts/e2e.sh " + $k)))
      and ($s | has("lint:md"))
  ' "$ROOT/package.json" >/dev/null
}

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

t_contract_describe_asks_only_the_listed_items() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; contract_main"
  _line=$(grep -F 'describe-task-definition' "$TMP/rec-aws" | head -n 1)
  must has_text "$_line" 'healthCheck'
  must has_text "$_line" 'networkMode'
  must has_text "$_line" 'dependsOn'
  if has_text "$_line" 'taskDefinitionArn'; then return 1; fi
}

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

t_entry_trap_exit_143_test_op_refuses_when_locked() {
  entry_setup || return 1
  lock_busy_setup || return 1
  _rc=0
  lib_call "$CI_FAKES; swsc_test_op" >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 1 ]
  must [ ! -s "$TMP/seq.log" ]
  must grep -Fxq other "$UNIT_LOCK/owner"
}

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

# ---- 信号以外の検査 第2区切り の検査（旧の check の名前と同じ。順序も旧と同じ） ----

# bats test_tags=unit
@test 'package.json の6つのscriptsがe2e.shへ委譲する' {
  t_package_json_delegates_six_scripts
}

# bats test_tags=unit
@test 'test:ci の不明なシナリオ名は、ロックと起動の前に終了コード2' {
  t_test_ci_unknown_scenario_exits_2_before_docker
}

# bats test_tags=unit
@test 'test:ci の名前指定は、子の終了コードを返し、ロックを解放する' {
  t_test_ci_scenarios_returns_child_rc_and_releases_lock
}

# bats test_tags=unit
@test 'contractは認証情報が無いと docker と aws を呼ばずに止まる' {
  t_contract_without_credentials_stops_before_docker_and_aws
}

# bats test_tags=unit
@test 'contractは test 以外の認証情報を拒否する' {
  t_contract_rejects_non_dummy_credentials
}

# bats test_tags=unit
@test 'contractは AWS_PROFILE を拒否する' {
  t_contract_rejects_aws_profile
}

# bats test_tags=unit
@test 'contractはダミー認証情報があれば前提を通り、最初に既存のswsc-ministackを消す' {
  t_contract_with_dummy_credentials_removes_old_ministack_first
}

# bats test_tags=unit
@test 'テンプレートは2コンテナのJSONで、awsvpc' {
  t_template_is_valid_json_with_two_containers
}

# bats test_tags=unit
@test '生成の結果はローカルのSquidにmockの宛先を渡す' {
  t_render_local_sets_upstream_and_mock_destination
}

# bats test_tags=unit
@test 'タスクレベルの固定値、ロールARNを書かない' {
  t_render_fixes_task_level_values_and_omits_roles
}

# bats test_tags=unit
@test 'Clientのプロキシ設定があり、healthCheckが無い' {
  t_client_has_proxy_settings_and_no_health_check
}

# bats test_tags=unit
@test 'contractは成功時、登録とdescribeの後に、最後に後始末する' {
  t_contract_success_registers_describes_and_removes_last
}

# bats test_tags=unit
@test 'contractの完成版はswsc_renderの出力と一致する' {
  t_contract_taskdef_is_the_swsc_render_output
}

# bats test_tags=unit
@test 'MiniStackの起動はlocalhostだけに公開し、ソケット、特権、latestを使わない' {
  t_contract_run_line_is_localhost_only_socketless_and_pinned
}

# bats test_tags=unit
@test 'ポートが使用中なら、MiniStackの起動の前に止まる' {
  t_contract_port_in_use_stops_before_docker_run
}

# bats test_tags=unit
@test '既存のswsc-ministackの削除は、ポート確認より前に行う' {
  t_contract_removes_old_ministack_before_port_check
}

# bats test_tags=unit
@test 'ラベルの無い同名コンテナは、消さずに起動の段階で止まる' {
  t_contract_never_removes_a_same_name_container_without_the_label
}

# bats test_tags=unit
@test 'MiniStackの起動に失敗したら、awsを呼ばずに後始末する' {
  t_contract_stops_when_docker_run_fails_without_aws_calls
}

# bats test_tags=unit
@test 'MiniStackが応答しなければ起動待ちで止まり、登録しない' {
  t_contract_stops_when_ministack_never_answers
}

# bats test_tags=unit
@test '登録の失敗は段階名を示して止まる' {
  t_contract_stops_at_registration_and_names_the_stage
}

# bats test_tags=unit
@test '比較の不一致は段階名を示して後始末する' {
  t_contract_mismatch_names_the_stage_and_removes
}

# bats test_tags=unit
@test '失敗時はcollectを後始末より前に呼ぶ' {
  t_contract_collects_on_failure_before_removal
}

# bats test_tags=unit
@test '失敗時にcollectが無くても後始末する' {
  t_contract_failure_without_collect_still_removes
}

# bats test_tags=unit
@test '成功時はcollectを呼ばない' {
  t_contract_success_never_collects
}

# bats test_tags=unit
@test 'TERMは終了コード143で、後始末をしてから止まる' {
  t_contract_terminate_exits_143_and_removes
}

# bats test_tags=unit
@test 'inspectの保存はマスクされ、公開ポートは127.0.0.1だけ' {
  t_contract_saves_masked_inspect_with_only_localhost_port
}

# bats test_tags=unit
@test 'describeは取り出す項目だけを求める' {
  t_contract_describe_asks_only_the_listed_items
}

# bats test_tags=unit
@test 'ポート確認は自分のswsc-を止めた後、構築の前に行い、使用中なら旧基盤を示して止まる' {
  t_start_checks_port_after_own_stop_and_before_build
}

# bats test_tags=unit
@test 'test:ciは成功時に start、test、collect、stop の順で1回ずつ呼ぶ' {
  t_test_ci_success_runs_start_test_collect_stop_once
}

# bats test_tags=unit
@test 'test:ciは start失敗でも collect を stop より前に呼び、rcを保つ' {
  t_test_ci_start_failure_collects_then_stops_and_keeps_rc
}

# bats test_tags=unit
@test 'test:ciは testの終了コードを保つ' {
  t_test_ci_test_failure_keeps_test_rc_and_collects
}

# bats test_tags=unit
@test 'test:ciは collect の失敗で終了コードを変えない' {
  t_test_ci_collect_failure_does_not_change_rc
}

# bats test_tags=unit
@test 'start操作は失敗時に stop だけを呼び、collect を呼ばない' {
  t_start_op_failure_stops_without_collect
}

# bats test_tags=unit
@test 'start操作は成功時に環境を残す（stopを呼ばない）' {
  t_start_op_success_keeps_environment
}

# bats test_tags=unit
@test 'test操作は通常の失敗で環境を残す' {
  t_test_op_failure_keeps_environment
}

# bats test_tags=unit
@test 'actionlint は式の誤りで失敗し、現在のワークフローでは成功する' {
  t_actionlint_rejects_expression_error
}

# bats test_tags=unit
@test 'Docker の失敗は管理対象の残存検査で status=1 になる（ゲートの定義から取り出して確かめる）' {
  t_managed_resource_check_failure
}

# bats test_tags=unit
@test '管理対象の残存が無ければ、ゲートの残存検査は status=0 のまま' {
  t_managed_resource_check_passes_when_empty_in_gate
}

# bats test_tags=unit
@test 'startはロックが既にあれば何も起動せず1を返し、他者のロックを消さない' {
  t_entry_trap_exit_143_start_refuses_when_locked
}

# bats test_tags=unit
@test 'startは成功でも失敗でも終了後にロックが無い' {
  t_entry_trap_exit_143_start_releases_lock_on_success_and_failure
}

# bats test_tags=unit
@test 'startはポート使用中なら作成せず1を返し、ロックを解放する' {
  t_entry_trap_exit_143_start_busy_port_creates_nothing_and_releases
}

# bats test_tags=unit
@test 'test:ciはロックを1回だけ取り、stopの最中は保持し、終了後に無い' {
  t_entry_trap_exit_143_test_ci_takes_lock_once_and_releases_after_stop
}

# bats test_tags=unit
@test 'test:ciはロックが既にあれば何も起動せず1を返す' {
  t_entry_trap_exit_143_test_ci_refuses_when_locked
}

# bats test_tags=unit
@test 'testはロックが既にあれば何も起動せず1を返す' {
  t_entry_trap_exit_143_test_op_refuses_when_locked
}

# bats test_tags=unit
@test 'stop、clean、logsはロックが残っていても動き、ロックに触れない' {
  t_entry_trap_exit_143_stop_clean_logs_ignore_lock
}

# bats test_tags=unit
@test 'contractは4566使用中なら MiniStack を作らず aws を呼ばず1を返し、ロックを解放する' {
  t_entry_trap_exit_143_contract_refuses_busy_4566_and_releases
}

# bats test_tags=unit
@test 'contractはロックが既にあれば何も起動せず1を返す' {
  t_entry_trap_exit_143_contract_refuses_when_locked
}

# ---- 信号の検査（旧の入口の関数を字句のまま移した）。子は lib_call の sh で起動し、信号は子へ送る ----

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

t_test_ci_signal_during_collect_still_stops() {
  entry_setup || return 1
  _rc=0
  # shellcheck disable=SC2016 # 単一引用符の中の変数と $$ は、lib_call の子の sh で展開する。$$ は子の sh の PID で、子へシグナルを送るための意図。親の PID にはしない。
  lib_call "$CI_FAKES; "'swsc_collect() { echo collect >>"$SWSC_TEST_SEQ"; if [ ! -f "$SWSC_TEST_DIR/sig-sent" ]; then : >"$SWSC_TEST_DIR/sig-sent"; kill -TERM $$; fi; return 0; }; swsc_test_ci_main' \
    >/dev/null 2>&1 || _rc=$?
  must [ "$_rc" -eq 143 ]
  must seq_is "$(printf 'start\ntest\ncollect\ncollect\nstop')"
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

t_entry_trap_exit_143_contract_term_releases_lock() {
  contract_setup || return 1
  contract_go "$CONTRACT_FREE; swsc_contract_wait_ready() { if [ -d \"\$SWSC_LOCK_DIR\" ]; then echo held >>\"\$SWSC_TEST_SEQ\"; fi; kill -TERM \$\$; return 0; }; swsc_collect() { :; }; contract_main"
  must [ "$RC" -eq 143 ]
  must grep -qxF held "$TMP/seq.log"
  must [ ! -e "$UNIT_LOCK" ]
}

# ---- 信号の検査の @test（旧の check の名前と同じ） ----

# bats test_tags=unit
@test 'test:ci の名前指定の TERM は143で、子を止めてからロックを解放する' {
  t_test_ci_scenarios_term_stops_child_and_releases_lock
}

# bats test_tags=unit
@test 'test:ciはcollectの最中にTERMを受けても、stopまで行う' {
  t_test_ci_signal_during_collect_still_stops
}

# bats test_tags=unit
@test 'test:ciのINTは130で、collectとstopを通る' {
  t_test_ci_interrupt_exits_130_and_still_collects_and_stops
}

# bats test_tags=unit
@test 'test:ciのTERMは143で、collectとstopを通る' {
  t_test_ci_terminate_exits_143_and_still_collects_and_stops
}

# bats test_tags=unit
@test 'test操作のINTは130で、stopを呼ぶ' {
  t_test_op_interrupt_stops_and_exits_130
}

# bats test_tags=unit
@test 'startのTERMは stop の後にロックを解放し、終了コード143' {
  t_entry_trap_exit_143_start_term_stops_then_releases_lock
}

# bats test_tags=unit
@test 'test:ciのINTは130で、collectとstopの後にロックが無い' {
  t_entry_trap_exit_143_test_ci_int_releases_after_stop
}

# bats test_tags=unit
@test 'test:ciのTERMは143で、collectとstopの後にロックが無い' {
  t_entry_trap_exit_143_test_ci_term_releases_after_stop
}

# bats test_tags=unit
@test 'testのTERMは143で、stopの後にロックが無い' {
  t_entry_trap_exit_143_test_op_term_releases_lock
}

# bats test_tags=unit
@test 'contractのTERMは143で、ロックが無い' {
  t_entry_trap_exit_143_contract_term_releases_lock
}

# ---- 契約の検査（前面で動く bats から、子の sh へ INT を送る） ----

t_contract_interrupt_exits_130_and_removes() {
  contract_setup || return 1
  touch "$TMP/aws-int"
  contract_go "$CONTRACT_FREE; contract_main"
  must [ "$RC" -eq 130 ]
  if grep -q 'register-task-definition' "$TMP/seq.log"; then return 1; fi
  must seq_last_is 'docker rm -f fakeid'
}

# bats test_tags=unit
@test 'INTは終了コード130で、後始末をしてから止まる' {
  t_contract_interrupt_exits_130_and_removes
}
