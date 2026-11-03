#!/bin/sh
# S14 の検査入口。開発用 Compose のホスト公開がループバックに限られることと、
# Squid の送信元 ACL の記述を確かめる。
# static は Docker のデーモンに接続しない。docker-compose config は設定を展開するだけなので、
# デーモンが止まっていても結果が変わらず、CI の前段でも同じ判定ができるようにするため。
# live は Compose を起動し、ホストから見た公開範囲と Squid の判定を確かめる。
# 実通信でポート 3128 と 8080 を使うため、実行は1回ずつにする。
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# 引数なしは static にする。品質ゲートが引数なしで呼んでも、スタックを起動しないようにするため。
MODE=${1:-static}

case "$MODE" in
  static) ;;
  live) ;;
  *)
    printf 'usage: sh tests/s14-compose-port-binding.sh static|live\n' >&2
    exit 2
    ;;
esac

cd "$ROOT"

failures=0
fail() { # 検査名
  failures=$((failures + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# 以降の live の処理は、Compose のスタックを実際に起動する。静的検査の trap を通さないよう、
# live は下の分岐で終わらせ、静的検査の処理へ進ませない。
LIVE_PROJECT=s14live

# 後始末は EXIT の trap に集める。シグナルで止まった場合も、EXIT の trap を通すため。
live_cleanup() {
  # 後始末の最中のシグナルで、down や rm を途中で止めないよう、シグナルを無視する。
  trap '' INT TERM
  # 途中で失敗しても残りの後始末は続ける。消し残しは検査の後に規則7の確認で見つける。
  docker-compose -p "$LIVE_PROJECT" down --remove-orphans >/dev/null 2>&1 \
    || printf '%s\n' 'live: 後始末の docker-compose down が失敗した' >&2
  if [ -n "$live_deny_dir" ]; then
    # rm -rf にせず、この検査が作ったファイル名だけを消す。残りがあれば rmdir が失敗して見える。
    rm -f "$live_deny_dir/squid.conf" "$live_deny_dir/broken.conf" "$live_deny_dir/override.yml"
    rmdir "$live_deny_dir" 2>/dev/null || printf '%s\n' 'live: .s14-deny の削除に失敗した' >&2
  fi
  if [ -n "$live_docker_config" ]; then
    rm -f "$live_docker_config/config.json"
    rmdir "$live_docker_config" 2>/dev/null || printf '%s\n' 'live: 空の Docker 設定の削除に失敗した' >&2
  fi
  if [ -n "$live_tmp" ]; then
    rm -f "$live_tmp/up.out" "$live_tmp/ps.out" "$live_tmp/host.body" "$live_tmp/client.out" \
      "$live_tmp/client.err" "$live_tmp/parse.out" "$live_tmp/broken.out" "$live_tmp/deny-up.out" \
      "$live_tmp/deny.log"
    rmdir "$live_tmp" 2>/dev/null || printf '%s\n' 'live: 作業用ディレクトリの削除に失敗した' >&2
  fi
}

# 検査を1つ行い、結果だけを出す。アドレスや識別情報は出さない（NFR-006）。
live_expect() { # 検査名 判定のコマンド...
  live_expect_name=$1
  shift
  if "$@"; then
    printf 'PASS: %s\n' "$live_expect_name"
  else
    fail "$live_expect_name"
  fi
}

# 起動直後は待ち受けが遅れるため、判定が通るまで1秒間隔で最大30回待つ（M05、M06と同じ）。
live_wait_until() { # 失敗時の検査名 判定の関数
  live_wait_name=$1
  live_wait_check=$2
  live_wait_i=0
  while [ "$live_wait_i" -lt 30 ]; do
    if "$live_wait_check"; then
      return 0
    fi
    live_wait_i=$((live_wait_i + 1))
    sleep 1
  done
  fail "$live_wait_name"
  return 1
}

live_wiremock_ready() {
  curl --fail --silent --max-time 2 --noproxy '' http://127.0.0.1:8080/__admin/mappings >/dev/null 2>&1
}

# Squid が応答すれば、対象外の要求には 403 が返る。接続できないときだけ 000 になる。
live_squid_answers_host() {
  live_code=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 \
    --noproxy '' --proxy http://127.0.0.1:3128 http://127.0.0.1/ 2>/dev/null || true)
  [ -n "$live_code" ] && [ "$live_code" != 000 ]
}

# 公開ポートを持たない squid は、コンテナ内の待ち受けで確かめる。ホストからは届かないため。
live_squid_listening() {
  docker-compose -p "$LIVE_PROJECT" exec -T squid bash -c 'exec 3<>/dev/tcp/127.0.0.1/3128' >/dev/null 2>&1
}

live_ports_loopback_only() {
  docker-compose -p "$LIVE_PROJECT" ps >"$live_tmp/ps.out" 2>&1 || return 1
  grep -Fq '127.0.0.1:3128->3128/tcp' "$live_tmp/ps.out" || return 1
  grep -Fq '127.0.0.1:8080->8080/tcp' "$live_tmp/ps.out" || return 1
  # 0.0.0.0 と :: が1つでもあると、全インターフェースへ公開されている。
  ! grep -Fq '0.0.0.0' "$live_tmp/ps.out" && ! grep -Fq '::' "$live_tmp/ps.out"
}

live_admin_200() {
  live_code=$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 --noproxy '' \
    http://127.0.0.1:8080/__admin/mappings 2>/dev/null || true)
  [ "$live_code" = 200 ]
}

# 非ループバックの IPv4 を1つ返す。見つからなければ何も返さない。値は検査の中でだけ使う。
live_nonloop_ip() {
  for live_iface in en0 en1; do
    live_ip=$(ipconfig getifaddr "$live_iface" 2>/dev/null || true)
    if [ -n "$live_ip" ]; then
      printf '%s\n' "$live_ip"
      return 0
    fi
  done
  live_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  case "$live_ip" in
    ''|127.*|*:*) return 1 ;;
  esac
  printf '%s\n' "$live_ip"
}

# 非ループバックのアドレスから接続できたら失敗にする。接続できれば HTTP のコードが出るため、000 以外で失敗とする。
live_refused() { # ポート番号
  live_code=$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 3 \
    --max-time 5 --noproxy '' "http://$live_nonloop:$1/" 2>/dev/null || true)
  [ "$live_code" = 000 ]
}

live_post_mapping() { # マッピングの JSON
  curl --fail --silent --show-error --noproxy '' -X POST http://127.0.0.1:8080/__admin/mappings \
    -H 'Content-Type: application/json' --data "$1" >/dev/null
}

live_post_mappings() {
  live_post_mapping '{"request":{"method":"GET","urlPath":"/s14-live/host"},"response":{"status":200,"body":"s14-host-ok"}}' \
    || return 1
  live_post_mapping '{"request":{"method":"GET","urlPath":"/s14-live/test-client"},"response":{"status":200,"body":"s14-client-ok"}}'
}

# Squid 経由で WireMock の本文が返るまで待つ。Squid の待ち受けだけでは、上流の準備を保証できない。
# 起動直後の最初の要求は、上流が準備できる前に届くことがあるため、本体の検査より前に待つ。
live_host_ready() {
  live_body=$(curl --silent --max-time 5 --noproxy '' --proxy http://127.0.0.1:3128 \
    http://api.example.com/s14-live/host 2>/dev/null) || return 1
  [ "$live_body" = 's14-host-ok' ]
}

live_host_allowed() {
  live_code=$(curl --silent --show-error --max-time 10 --noproxy '' --proxy http://127.0.0.1:3128 \
    --output "$live_tmp/host.body" --write-out '%{http_code}' http://api.example.com/s14-live/host || true)
  # 失敗時はステータスだけを出す。起動直後の一時的な失敗かを、後から判別するため。
  if [ "$live_code" != 200 ]; then
    printf 'diag: 許可ドメインの要求の HTTP ステータス=%s\n' "$live_code" >&2
    return 1
  fi
  [ "$(cat "$live_tmp/host.body")" = 's14-host-ok' ]
}

live_host_denied_offlist() {
  live_code=$(curl --silent --max-time 10 --noproxy '' --proxy http://127.0.0.1:3128 \
    --output /dev/null --write-out '%{http_code}' http://example.com/ 2>/dev/null || true)
  [ "$live_code" = 403 ]
}

# one-shot の Test Client を1回だけ実行する。exec は、常駐していない Test Client に使えないため使わない。
live_run_client() {
  docker-compose -p "$LIVE_PROJECT" run -T --rm --no-deps -e TEST_API_PATH=/s14-live/test-client test-client \
    >"$live_tmp/client.out" 2>"$live_tmp/client.err"
}

live_client_200() {
  live_run_client && grep -Fxq 'CLIENT_STATUS=200' "$live_tmp/client.out"
}

live_client_403() {
  live_run_client && grep -Fxq 'CLIENT_STATUS=403' "$live_tmp/client.out"
}

live_parse_current() {
  docker-compose -p "$LIVE_PROJECT" exec -T squid squid -k parse >"$live_tmp/parse.out" 2>&1 || return 1
  ! grep -Eq 'ERROR|FATAL' "$live_tmp/parse.out"
}

# 終了コードだけでなく、未定義のディレクティブを指す出力も確かめる。
# 別の理由で終了コードが非0になった場合（起動の失敗など）に、通ったことにしないため。
live_parse_broken() {
  if docker-compose -p "$LIVE_PROJECT" run -T --rm --no-deps \
    -v "$live_deny_dir/broken.conf:/etc/squid/broken.conf:ro" \
    squid squid -k parse -f /etc/squid/broken.conf >"$live_tmp/broken.out" 2>&1; then
    return 1
  fi
  grep -Fq 'unrecognized' "$live_tmp/broken.out"
}

# 範囲外の送信元の検査に使う写しを作る。ホストの一時ディレクトリは VM に見えないことがあるため、
# リポジトリ直下に作る（plan.md 4.3）。既存のディレクトリは消さないよう、mkdir の失敗で止める。
live_prepare_deny_dir() {
  if ! mkdir "$ROOT/$live_deny_name" 2>/dev/null; then
    fail 'live: .s14-deny の作成に失敗した（同名の既存のディレクトリがある）'
    return 1
  fi
  live_deny_dir="$ROOT/$live_deny_name"
  sed -e 's|^acl local_src src .*$|acl local_src src 192.0.2.0/24|' squid-config/squid.conf \
    >"$live_deny_dir/squid.conf"
  # 置き換えたのが acl の1行だけであることを確かめる。ほかの行を壊すと、判定の意味が変わるため。
  if [ "$(grep -Fxc 'acl local_src src 192.0.2.0/24' "$live_deny_dir/squid.conf")" -ne 1 ]; then
    fail 'live: 送信元 ACL の差し替えが1行にならなかった'
    return 1
  fi
  # ports を空にして、本番の 127.0.0.1 公開を作らない。volumes は同じ宛先を上書きする。
  cat >"$live_deny_dir/override.yml" <<EOF
services:
  squid:
    ports: !reset []
    volumes:
      - ./$live_deny_name/squid.conf:/etc/squid/squid.conf:ro
EOF
  cat squid-config/squid.conf >"$live_deny_dir/broken.conf"
  printf '%s\n' 's14_undefined_directive_for_check on' >>"$live_deny_dir/broken.conf"
}

# 範囲外の写しで squid だけを作り直す。ports が空なので、ホストからは届かない。
live_deny_up() {
  if ! docker-compose -p "$LIVE_PROJECT" -f docker-compose.yml -f "$live_deny_dir/override.yml" \
    up -d --force-recreate squid >"$live_tmp/deny-up.out" 2>&1; then
    fail '範囲外の送信元の検査: squid を作り直せなかった'
    return 1
  fi
  live_wait_until '範囲外の検査で squid が待ち受けない' live_squid_listening
}

live_deny_log() {
  docker-compose -p "$LIVE_PROJECT" exec -T squid cat /var/log/squid/access.log >"$live_tmp/deny.log" 2>/dev/null \
    || return 1
  grep -F 'TCP_DENIED/403' "$live_tmp/deny.log" | grep -Fq '/s14-live/test-client'
}

live_main() {
  live_docker_config=
  live_deny_dir=
  live_tmp=
  live_nonloop=
  live_deny_name=".s14-deny.$$"

  # 途中で止まっても後始末を通す。EXIT の trap を、INT と TERM の終了からも通す。
  trap live_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # Colima が動くときだけ、Colima の Docker ソケットを使う。
  if command -v colima >/dev/null 2>&1 && colima status >/dev/null 2>&1; then
    DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
    export DOCKER_HOST
  fi

  # Docker の設定ファイルが読めない環境（サンドボックスの Operation not permitted）だけ、
  # 空の設定に差し替える。読める環境では利用者の Docker context をそのまま使う。
  if [ -e "$HOME/.docker/config.json" ] && [ ! -r "$HOME/.docker/config.json" ]; then
    live_docker_config=$(mktemp -d) || { fail 'live: 空の Docker 設定の作成に失敗した'; return 1; }
    printf '{}\n' >"$live_docker_config/config.json"
    DOCKER_CONFIG="$live_docker_config"
    export DOCKER_CONFIG
  fi
  # 作業用の場所は mktemp で作る。失敗は後続に流さず、この場で止める。
  live_tmp=$(mktemp -d) || { fail 'live: 作業用ディレクトリの作成に失敗した'; return 1; }

  # 前回の残りを消す（NFR-007）。down の失敗は、続く up の失敗として現れる。
  docker-compose -p "$LIVE_PROJECT" down --remove-orphans >/dev/null 2>&1 || true

  if ! docker-compose -p "$LIVE_PROJECT" -f docker-compose.yml up -d squid wiremock >"$live_tmp/up.out" 2>&1; then
    fail 'docker-compose up -d squid wiremock が失敗した'
    return 1
  fi
  live_wait_until 'WireMock の管理 API が応答しない' live_wiremock_ready || return 1
  live_wait_until 'Squid がプロキシとして応答しない' live_squid_answers_host || return 1

  live_expect '公開ポートが 127.0.0.1 の2件だけである' live_ports_loopback_only
  live_expect '127.0.0.1:8080 の管理 API が 200 を返す' live_admin_200

  # 非ループバックのアドレスが得られない環境（Linux の CI など）では、この検査を省く。
  live_nonloop=$(live_nonloop_ip || true)
  if [ -z "$live_nonloop" ]; then
    printf '%s\n' 'SKIP: 非ループバックの IPv4 を取得できないため、接続拒否の検査を省いた'
  else
    live_expect '非ループバックのアドレスから 3128 へ接続できない' live_refused 3128
    live_expect '非ループバックのアドレスから 8080 へ接続できない' live_refused 8080
  fi

  live_expect 'WireMock に許可ドメインと Test Client 用のマッピングを投入できる' live_post_mappings
  live_wait_until 'Squid 経由で WireMock の本文が返らない' live_host_ready || return 1
  live_expect 'ホストから許可ドメインが 200 と本文を返す' live_host_allowed
  live_expect 'ホストから許可外ドメインが 403 になる' live_host_denied_offlist

  live_expect 'Test Client の one-shot 実行が終了コード 0 で CLIENT_STATUS=200 を出す' live_client_200

  live_expect '現行の設定で squid -k parse が成功し、ERROR と FATAL がない' live_parse_current
  if live_prepare_deny_dir; then
    live_expect '未定義のディレクティブを含む写しで squid -k parse が非0で終わる' live_parse_broken
  else
    return 1
  fi

  # 範囲外の検査は最後に置く。squid を作り直すため、それより前の検査に影響させないため。
  if live_deny_up; then
    live_expect '範囲外の送信元の Test Client が 403 になる' live_client_403
    live_expect 'Squid のアクセスログに TCP_DENIED/403 が出る' live_deny_log
  else
    return 1
  fi

  if [ "$failures" -ne 0 ]; then
    return 1
  fi
  printf '%s\n' 's14 live passed'
  return 0
}

if [ "$MODE" = live ]; then
  live_rc=0
  live_main || live_rc=$?
  if [ "$live_rc" -ne 0 ]; then
    printf '%s\n' 's14 live: failed' >&2
  fi
  exit "$live_rc"
fi

# 展開結果と標準エラーの保存先。リポジトリ直下には作らず、終了時に必ず消す。
# 空のときに rm -rf を走らせないため、作成の後にだけ変数を設定する。
tmp_dir=
cleanup() {
  if [ -n "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tmp_dir=$(mktemp -d)

# 設定が展開できない場合、以降の検査は前提が崩れるため、ここで止める。
if ! docker-compose config --quiet 2>"$tmp_dir/compose.err"; then
  fail "docker-compose config --quiet が失敗した"
  cat "$tmp_dir/compose.err" >&2
  exit 1
fi

compose_json="$tmp_dir/compose.json"
if ! docker-compose config --format json >"$compose_json" 2>"$tmp_dir/compose.err"; then
  fail "docker-compose config --format json が失敗した"
  cat "$tmp_dir/compose.err" >&2
  exit 1
fi

# YAML を文字列で読むと、ポートの書き方の揺れ（引用符や省略形）に弱い。
# 展開後の JSON を読むことで、Compose が実際に公開する値を確かめる。
if ! python3 - "$compose_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    config = json.load(stream)

services = config.get("services", {})
problems = []

# サービス名とネットワーク名は、Test Client の接続先（squid、wiremock）と既存の検査が前提にする。
if sorted(services) != ["squid", "test-client", "wiremock"]:
    problems.append("サービス名が想定と違う: " + ", ".join(sorted(services)))
if sorted(config.get("networks", {})) != ["sidecar"]:
    problems.append("ネットワークが sidecar だけではない")

# host_ip を省くと全インターフェースへ開くため、127.0.0.1 を明示した1件だけを許す。
for name, port in (("squid", 3128), ("wiremock", 8080)):
    ports = services.get(name, {}).get("ports") or []
    if len(ports) != 1:
        problems.append(f"{name} の公開ポートが1件ではない")
        continue
    entry = ports[0]
    if (
        entry.get("target") != port
        or str(entry.get("published")) != str(port)
        or entry.get("host_ip") != "127.0.0.1"
    ):
        problems.append(f"{name} の公開ポートが 127.0.0.1:{port} ではない")

# Test Client は Compose 内部だけで Squid に届けばよい。ホストへ公開すると、公開面が増える。
for name, service in services.items():
    if name not in ("squid", "wiremock") and service.get("ports"):
        problems.append(f"{name} に公開ポートがある")

# 環境変数の値は、Test Client が Squid と WireMock を見つける既存の契約そのもの。
expected_env = {
    "HTTP_PROXY": "http://squid:3128",
    "HTTPS_PROXY": "http://squid:3128",
    "NO_PROXY": "localhost,127.0.0.1,squid,wiremock",
    "TEST_API_BASE_URL": "http://api.example.com",
}
test_env = services.get("test-client", {}).get("environment") or {}
for key, value in expected_env.items():
    if test_env.get(key) != value:
        problems.append(f"test-client の {key} が既存の値と違う")

# 設定とマッピングは読み取り専用でマウントする。コンテナ側から書き換えられると、検査の前提が崩れる。
for name in ("squid", "wiremock"):
    for volume in services.get(name, {}).get("volumes") or []:
        if volume.get("read_only") is not True:
            problems.append(f"{name} のマウント {volume.get('target')} が読み取り専用ではない")

for problem in problems:
    print("FAIL: " + problem, file=sys.stderr)
sys.exit(1 if problems else 0)
PY
then
  fail "docker-compose の展開結果（公開範囲、契約の不変）"
fi

# Squid は送信元 ACL の行が完全一致で存在することで判定する。
# 部分一致だと、コメントや別の行の一部に誤って一致してしまうため。
squid_conf=squid-config/squid.conf
expect_squid_line() { # 検査名 完全一致させる行
  if ! grep -Fxq -- "$2" "$squid_conf"; then
    fail "$1"
  fi
}
expect_squid_line "送信元 ACL の行が規定の4範囲と一致する" \
  'acl local_src src 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16'
expect_squid_line "送信元を見る許可行がある" 'http_access allow local_src api_domains'
expect_squid_line "最後の拒否行がある" 'http_access deny all'
expect_squid_line "キャッシュ無効の行がある" 'cache deny all'
# 送信元を見ない旧い許可行が残ると、範囲外の送信元が許可ドメインへ届いてしまう。
if [ "$(grep -c '^http_access ' "$squid_conf")" -ne 2 ]; then
  fail "http_access の行は、許可と拒否の2行だけであること"
fi
if grep -Fxq -- 'http_access allow api_domains' "$squid_conf"; then
  fail "送信元を見ない旧い許可行（http_access allow api_domains）が残っている"
fi

# 許可ドメインは、有効な行（空行と # のコメントを除く）が規定の2件だけであること。
whitelist_expected="$tmp_dir/whitelist.expected"
whitelist_actual="$tmp_dir/whitelist.actual"
printf 'api.example.com\napi-staging.example.com\n' >"$whitelist_expected"
sed -e 's/[[:space:]]*$//' squid-config/whitelist.txt | grep -Ev '^(#|$)' >"$whitelist_actual" || true
if ! cmp -s "$whitelist_expected" "$whitelist_actual"; then
  fail "許可ドメインの有効な行が規定の2件と一致しない"
fi

# 識別情報は、公開用の文書と設定に含めない。検査の対象は、存在するファイルだけを読む。
identity_pattern='[0-9]{12}|arn:aws|AKIA|aws_secret'
identity_files="docker-compose.yml squid-config/squid.conf scripts/quality-gate.sh README.md
docs/ポート公開範囲.md docs/シナリオ隔離.md
specs/S14-compose-port-binding/live-check.md specs/S14-compose-port-binding/contract-impact.md
specs/S14-compose-port-binding/security-review.md"
for file in $identity_files; do
  [ -f "$file" ] || continue
  if grep -Eq -- "$identity_pattern" "$file"; then
    fail "識別情報らしい文字列がある: $file"
  fi
done
# 展開結果にも識別情報がないことを、保存した出力で確かめる。
if grep -Eq -- "$identity_pattern" "$compose_json"; then
  fail "docker-compose の展開結果に識別情報らしい文字列がある"
fi

# 文書は、接続先と公開範囲の理由を利用者が読む入口になる。節や接続先の記述が消えても
# 他の検査は通るため、文書の記述を別に確かめる。
policy_doc=docs/ポート公開範囲.md
if [ ! -f "$policy_doc" ]; then
  fail "docs/ポート公開範囲.md がない"
else
  for heading in 概要 接続先 'Squid の送信元制御' '許可ネットワークを採用しない理由' \
    '別マシンや別コンテナから使う場合' '症状と対処' 'M10 への引き継ぎ'; do
    grep -Fxq -- "## $heading" "$policy_doc" || fail "docs/ポート公開範囲.md に節がない: $heading"
  done
  # 見出しが2つ以上あると、文書の表題が一意に定まらず、検索や目次の表示が崩れる。
  if [ "$(grep -c '^# ' "$policy_doc")" -ne 1 ]; then
    fail "docs/ポート公開範囲.md の # 見出しが1つではない"
  fi
fi

# README は、System Components の公開先が 127.0.0.1 であることと、文書へのリンクを確かめる。
# ECS モデルの localhost は残すため、行全体の一致で判定する。
for line in '- 127.0.0.1:3128 でリッスン' '- REST API mock server（127.0.0.1:8080）'; do
  grep -Fxq -- "$line" README.md || fail "README の System Components が 127.0.0.1 になっていない: $line"
done
grep -Fq '(docs/ポート公開範囲.md)' README.md || fail "README に docs/ポート公開範囲.md へのリンクがない"

# 公開の記述は「ポートとコンテナ」の行にある。そこから 127.0.0.1 が消えると、公開先が読めなくなる。
if ! grep -F 'ポートとコンテナ' docs/シナリオ隔離.md | grep -Fq '127.0.0.1'; then
  fail "docs/シナリオ隔離.md の公開ポートの記述に 127.0.0.1 がない"
fi

if [ "$failures" -ne 0 ]; then
  printf 's14 static: %s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 's14 static passed\n'
