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

# core.quotepathをオフにし、日本語のパスを引用符なしで扱う
changed=$( {
  git -c core.quotepath=off diff --name-only "$base_ref"...HEAD
  git -c core.quotepath=off diff --cached --name-only
  git -c core.quotepath=off diff --name-only
  git -c core.quotepath=off ls-files --others --exclude-standard
} | sort -u)

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
if has_match '^(docker-compose\.yml|Dockerfile|squid-config/|wiremock-scenarios/|test-client/|tests/)'; then
  run docker-compose config --quiet
  for test in tests/m0*.sh; do
    [ -f "$test" ] || continue
    if has_match "^$test\$|^(docker-compose\.yml|Dockerfile|squid-config/|wiremock-scenarios/|test-client/)"; then
      run sh "$test"
    fi
  done
  if [ -n "$(docker-compose ps -aq 2>/dev/null || true)" ]; then
    printf 'FAILED: 統合テスト後にコンテナが残っている\n' >&2
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  printf '%s\n' 'quality-gate: passed'
else
  printf '%s\n' 'quality-gate: failed' >&2
fi
exit "$status"
