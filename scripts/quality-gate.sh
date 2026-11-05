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

# 共通ゲート: 差分、コミット済み範囲、シェル構文
run git diff --check
run git diff --cached --check
run git -c core.quotepath=off diff --check "$base_ref"...HEAD
for script in tests/*.sh test-client/*.sh scripts/*.sh; do
  [ -f "$script" ] || continue
  run sh -n "$script"
done

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

# Compose、Dockerfile、Squid、WireMock、Test Client、統合テストの変更
if has_match '^(docker-compose\.yml|Dockerfile|squid-config/|wiremock-scenarios/|test-client/|tests/|scripts/scenario-lib\.sh)'; then
  run docker-compose config --quiet
  # 自らComposeのライフサイクルを管理するスモークだけを、変更範囲に応じて実行する。
  # M02は稼働中のスタックを前提とし、ゲートから起動するとWireMockへ接続できず失敗するため、
  # AGENTS.mdの方針どおり個別に実行する。
  printf '%s\n' 'NOTE: tests/m02-routing-smoke.sh は稼働中のスタックが必要なため、ゲートでは実行しない'
  for test in tests/m03-wiremock-scenarios.sh tests/m04-test-client.sh tests/m05-proxy-integration.sh tests/m06-client-resilience.sh tests/m07-scenario-isolation.sh tests/m08-e2e-suite.sh tests/s14-compose-port-binding.sh; do
    [ -f "$test" ] || continue
    if has_match "^$test\$|^(docker-compose\.yml|Dockerfile|squid-config/|wiremock-scenarios/|test-client/|scripts/scenario-lib\.sh)"; then
      run sh "$test"
    fi
  done
  if [ -n "$(docker-compose ps -aq 2>/dev/null || true)" ]; then
    printf 'FAILED: 統合テスト後にコンテナが残っている\n' >&2
    status=1
  fi
  # M08 は m08-e2e プロジェクトで動くため、既定のプロジェクトだけでは残りを見逃す。
  if [ -n "$(COMPOSE_PROJECT_NAME=m08-e2e docker-compose ps -aq 2>/dev/null || true)" ]; then
    printf 'FAILED: M08 のコンテナ（m08-e2e）が残っている\n' >&2
    status=1
  fi
fi

# M09 の E2E 基盤。unit は Docker と AWS CLI を使わず、smoke は Docker を使うが AWS CLI と認証情報を使わない。
# Why: tests/m09-execution-and-ci.sh は引数なしだと smoke を既定にするため、既存の for ループに混ぜると
# モードを明示せずに Docker を使ってしまう。unit と smoke を、この順に別の run で呼ぶ。
# Why not: contract は、ダミー認証情報の環境変数が要り、エージェントのシェルでは設定できないため登録しない。
if has_match '^(scripts/e2e|ecs/|tests/m09-execution-and-ci\.sh$|\.github/workflows/e2e-test\.yml$|docs/ローカル実行とCI\.md$|package\.json$|\.gitignore$|squid-config/|test-client/|wiremock-scenarios/|Dockerfile)'; then
  printf '%s\n' 'NOTE: tests/m09-execution-and-ci.sh contract は利用者の端末と CI だけで実行するため、ゲートでは実行しない'
  run sh tests/m09-execution-and-ci.sh unit
  run sh tests/m09-execution-and-ci.sh smoke
  # Why: smoke の途中で止まると swsc- のコンテナが残るため、既存の M08 と同じく、ブロックの最後に残存を確かめる。
  if [ -n "$(docker ps -aq --filter label=swsc.managed=true 2>/dev/null || true)" ]; then
    printf '%s\n' 'FAILED: M09 のコンテナ（swsc-）が残っている' >&2
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  printf '%s\n' 'quality-gate: passed'
else
  printf '%s\n' 'quality-gate: failed' >&2
fi
exit "$status"
