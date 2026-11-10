#!/usr/bin/env bats
# M09 の静的な検査（群1: t_wf_、t_gate_、t_mise_、t_gitleaks_、t_json_、t_bats_、t_run_bats_）。
# Docker と AWS CLI を使わず、ワークフロー、ゲート、設定ファイルの中身を確かめる。
# 旧の tests/m09-execution-and-ci.sh の check の名前を、そのまま @test の名前にした。
# 検査の本体は旧の入口の関数を字句のまま移した。入口の補助（must、rc_is、gate_has など）は、
# 入口を M09_LIB_ONLY=1 で読み込んで使う。
# shellcheck disable=SC2034,SC2329 # 入口（tests/m09-execution-and-ci.sh）を . で読み込んで使う。WF などは入口が読み、関数は @test から呼ぶ。shellcheck は別ファイルを追えないため、この2件を外す。

load 'helpers/common'

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  cd "$ROOT" || return 1
  common_setup_tmp
  SELF=$ROOT/tests/m09-execution-and-ci.sh
  # 入口は $1 をモードとして読む。bats が渡す引数（検査の名前）を消してから読み込む。
  set --
  # 入口の関数と変数だけを読む。M09_LIB_ONLY=1 のときは、本体（検査の実行）を走らせない。
  M09_LIB_ONLY=1
  M09_LIB_ROOT=$ROOT
  # shellcheck source=/dev/null
  . "$SELF"
  unset M09_LIB_ONLY M09_LIB_ROOT
  # 入口は set -eu で読み込まれる。bats の変数を守るため、-u を戻す。
  set +eu
}

teardown() {
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
