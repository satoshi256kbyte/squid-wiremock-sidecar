#!/bin/sh
# 変更範囲に応じた品質ゲートを1つの入口から実行する。
# AGENTS.mdの「変更範囲別の品質ゲート」表に対応する。
# 手作業でゲートを組み立てると実行漏れが起きるため、この入口に集約する。
set -eu

base_ref="${QUALITY_GATE_BASE:-origin/main}"
repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# 基点が解決できない場合は、比較を省いて成功にせず停止する
if ! git rev-parse --verify -q "$base_ref" >/dev/null 2>&1; then
  printf 'FAILED: 基点 %s が解決できない。git fetch origin main を実行するか QUALITY_GATE_BASE を指定する\n' \
    "$base_ref" >&2
  exit 1
fi

if command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
  export DOCKER_HOST=unix:///Users/satoshi/.colima/default/docker.sock
fi

# core.quotepathをオフにし、日本語のパスを引用符なしで扱う。
# 各gitを個別の代入で実行する。パイプラインにすると、gitの失敗が後段のsortの終了コードに隠れ、
# 変更が欠けたままゲートが通ってしまうため。
committed=$(git -c core.quotepath=off diff --name-only "$base_ref"...HEAD)
staged=$(git -c core.quotepath=off diff --cached --name-only)
unstaged=$(git -c core.quotepath=off diff --name-only)
untracked=$(git -c core.quotepath=off ls-files --others --exclude-standard)
changed=$(printf '%s\n%s\n%s\n%s\n' "$committed" "$staged" "$unstaged" "$untracked" | sort -u)

printf '%s\n' "$changed" | sed '/^$/d' | sed 's/^/変更: /'

has_match() {
  printf '%s\n' "$changed" | grep -Eq "$1"
}

status=0
run() {
  printf '==> %s\n' "$*"
  if ! "$@"; then
    printf 'FAILED: %s\n' "$*" >&2
    status=1
  fi
}

# 管理対象（接頭辞 swsc- とラベル swsc.managed=true の両方に一致）の残存を確かめる。
# Why: swsc_check_managed_empty は Docker の失敗を残存なしと区別して1を返すため、|| true で隠さない。
# Why: e2e-lib.sh は部分シェルで読み込み、その変数を品質ゲートの本体へ漏らさない。
managed_check() { # 失敗時の説明
  if ! (. "$repo_root/scripts/e2e-lib.sh" && swsc_check_managed_empty); then
    printf 'FAILED: %s\n' "$1" >&2
    status=1
  fi
}

# 共通ゲート: 差分、コミット済み範囲
run git diff --check
run git diff --cached --check
run git -c core.quotepath=off diff --check "$base_ref"...HEAD

# シェルの静的解析: 固定版の shellcheck を mise which の実体で動かし、対象の .sh をすべて検査する。
# Why: PATH 上の別の shellcheck や、実行時の自動導入に頼ると、結果が環境で変わるため。
# Why: 自動の導入を止める2つの環境変数と MISE_LOCKED=1 を、mise を呼ぶ各コマンドへ付ける。export はしない。
# Why: mise の取得は if ! で受ける。var=$(...) で直接受けると set -e で止まり、導入手順を出せないため。
# Why: git ls-files は一時ファイルへ書いて終了コードを見る。パイプにすると git の失敗が隠れ、空の一覧が通るため。
shellcheck_gate() {
  if ! command -v mise >/dev/null 2>&1; then
    printf '%s\n' 'FAILED: miseが未導入。miseを導入し、mise install --lockedを実行する（docs/ローカル実行とCI.md）' >&2
    status=1
    return 0
  fi
  if ! expected=$(MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise current shellcheck 2>/dev/null) \
    || [ -z "$expected" ]; then
    printf '%s\n' 'FAILED: shellcheckの期待する版を mise current で得られない。mise install --lockedを実行する' >&2
    status=1
    return 0
  fi
  if ! actual_path=$(MISE_EXEC_AUTO_INSTALL=false MISE_AUTO_INSTALL=false MISE_LOCKED=1 mise which shellcheck 2>/dev/null) \
    || [ -z "$actual_path" ]; then
    printf '%s\n' 'FAILED: shellcheckが未導入。mise install --lockedを実行する' >&2
    status=1
    return 0
  fi
  if ! version_out=$("$actual_path" --version); then
    printf '%s\n' 'FAILED: shellcheck --version が失敗した。mise install --lockedを実行する' >&2
    status=1
    return 0
  fi
  actual=$(printf '%s\n' "$version_out" | sed -n 's/^version: //p')
  if [ "$actual" != "$expected" ]; then
    printf 'FAILED: shellcheckの版が期待と異なる（期待 %s、実際 %s）。mise install --lockedを実行する\n' \
      "$expected" "$actual" >&2
    status=1
    return 0
  fi
  if ! tmp_list=$(mktemp); then
    printf '%s\n' 'FAILED: 一時ファイルを作れない' >&2
    status=1
    return 0
  fi
  trap 'rm -f "$tmp_list"' EXIT
  # Why: 割り込みと終了要求でも、exit を経由して EXIT トラップを走らせ、一時ファイルを消すため。
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if ! git ls-files -z -co --exclude-standard '*.sh' >"$tmp_list"; then
    printf '%s\n' 'FAILED: git ls-files が失敗した' >&2
    status=1
  elif [ ! -s "$tmp_list" ]; then
    printf '%s\n' 'FAILED: 検査対象の .sh が0件。空の一覧は成功にしない' >&2
    status=1
  else
    # Why: 先頭が - のファイル名を shellcheck にオプションとして解釈させないため、-- で区切る。
    run xargs -0 "$actual_path" -s sh -S style -- <"$tmp_list"
  fi
  rm -f "$tmp_list"
  trap - EXIT
  trap - INT TERM
}
shellcheck_gate

# Markdownゲート: 固定版のmarkdownlint-cli2で全Markdownを検査する。
# 設定ファイルや依存の変更でも、規則の影響を確認するため実行する。
# 依存が未導入の場合は成功扱いにせず、導入手順を示して失敗させる。
if has_match '(\.md$|^package(-lock)?\.json$|^\.markdownlint\.json$)'; then
  if [ ! -x node_modules/.bin/markdownlint-cli2 ]; then
    printf '%s\n' 'FAILED: markdownlint-cli2が未導入。npm ciを実行する' >&2
    status=1
  else
    run npm run -s lint:md
  fi
fi

# Squid、WireMock、Test Client、統合テストの変更
if has_match '^(Dockerfile|squid-config/|wiremock-scenarios/|test-client/|tests/|scripts/scenario-lib\.sh)'; then
  # M02〜M08 は自分で起動と停止を行い、ロック、trap、cleanup を持つ。稼働中のスタックは前提にしない。
  for test in tests/m02-routing-smoke.sh tests/m03-wiremock-scenarios.sh tests/m04-test-client.sh tests/m05-proxy-integration.sh tests/m06-client-resilience.sh tests/m07-scenario-isolation.sh tests/m08-e2e-suite.sh; do
    [ -f "$test" ] || continue
    if has_match "^$test\$|^(Dockerfile|squid-config/|wiremock-scenarios/|test-client/|scripts/scenario-lib\.sh)"; then
      run sh "$test"
    fi
  done
  # 統合テストの後に、管理対象の資源が残っていないことを確かめる。Docker の失敗も残存として扱う。
  managed_check '統合テストの後に管理対象の資源（swsc-）が残っている、または確かめられない'
fi

# S14 の契約検査。Docker を使わない unit で、Compose の展開は見ない。
# Why: 契約の入力（e2e-runner.sh のポート公開とマウント、e2e-taskdef.py、ecs/ のタスク定義と派生設定）だけの変更でも、
# Squid の非公開と mapping の読み取り専用を確かめるため、統合テストとは別の条件で1回だけ呼ぶ（evidence-code-review の SHOULD）。
# Why: 条件は変数に置く。M09 のブロックの if 行（scripts/e2e を含む）と、行の形で区別できるようにするため。
s14_inputs='^(Dockerfile|squid-config/|wiremock-scenarios/|test-client/|tests/|scripts/scenario-lib\.sh|scripts/e2e|ecs/)'
if has_match "$s14_inputs"; then
  run sh tests/s14-taskdef-contract.sh unit
fi

# M09 の E2E 基盤。unit は Docker と AWS CLI を使わず、smoke は Docker を使うが AWS CLI と認証情報を使わない。
# Why: tests/m09-execution-and-ci.sh は引数なしだと smoke を既定にするため、既存の for ループに混ぜると
# モードを明示せずに Docker を使ってしまう。unit と smoke を、この順に別の run で呼ぶ。
# Why not: contract は、ダミー認証情報の環境変数が要り、エージェントのシェルでは設定できないため登録しない。
if has_match '^(scripts/e2e|ecs/|tests/m09-execution-and-ci\.sh$|\.github/workflows/e2e-test\.yml$|docs/ローカル実行とCI\.md$|package\.json$|\.gitignore$|squid-config/|test-client/|wiremock-scenarios/|Dockerfile)'; then
  printf '%s\n' 'NOTE: tests/m09-execution-and-ci.sh contract は利用者の端末と CI だけで実行するため、ゲートでは実行しない'
  run sh tests/m09-execution-and-ci.sh unit
  run sh tests/m09-execution-and-ci.sh smoke
  # Why: smoke の途中で止まると swsc- のコンテナが残るため、ブロックの最後に残存を確かめる。
  managed_check 'M09 のコンテナ（swsc-）が残っている、または確かめられない'
fi

if [ "$status" -eq 0 ]; then
  printf '%s\n' 'quality-gate: passed'
else
  printf '%s\n' 'quality-gate: failed' >&2
fi
exit "$status"
