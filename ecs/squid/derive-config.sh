#!/bin/sh
# Squid の設定を SQUID_UPSTREAM に応じて派生させる（M09 FR-908、plan 3.4）。
# 使い方: derive-config.sh <派生元 squid.conf> <出力先>
# Why: squid-config/squid.conf を単一の情報源にし、上流だけを環境変数で切り替えるため。
# Why not 正規表現の置換: 派生元の行を完全一致で数えないと、似た行を誤って書き換えるため。
set -eu

if [ $# -ne 2 ]; then
  printf 'swsc-derive: 使い方: derive-config.sh <派生元> <出力先>\n' >&2
  exit 2
fi
src=$1
dst=$2

fail() {
  printf 'swsc-derive: %s\n' "$*" >&2
  exit 1
}

# 派生の対象になる行。派生元の書式が変わったら、ここで気づけるように完全一致で固定する。
LINE_PEER='cache_peer wiremock parent 8080 0 no-query'
LINE_ALLOW='cache_peer_access wiremock allow api_domains'
LINE_DENY='cache_peer_access wiremock deny all'
LINE_NEVER='never_direct allow api_domains'

upstream=${SQUID_UPSTREAM-}
case $upstream in
  mock | direct) ;;
  *) fail 'SQUID_UPSTREAM は mock か direct のどちらか（完全一致）' ;;
esac

# 派生元の必須の行が、それぞれ1行ずつ存在することを確かめる。
for line in "$LINE_PEER" "$LINE_ALLOW" "$LINE_DENY" "$LINE_NEVER"; do
  n=$(LINE="$line" awk '$0 == ENVIRON["LINE"] { n++ } END { print n + 0 }' "$src")
  if [ "$n" -ne 1 ]; then
    fail "派生元に必須の行が1行だけ無い: $line"
  fi
done

if [ "$upstream" = mock ]; then
  host=${SQUID_MOCK_HOST-}
  port=${SQUID_MOCK_PORT-}
  # 英数字、.、- だけを許す。Why: 設定ファイルへ書く値に、空白や ; を入れて別の指示を混ぜないため。
  case $host in
    '' | *[!A-Za-z0-9.-]*) fail 'SQUID_MOCK_HOST は英数字、.、- だけ' ;;
  esac
  # Why: ?????* は5文字以上に一致する。5桁（10000〜65535）を拒否しないよう、6文字以上を弾く。範囲は下で見る。
  case $port in
    '' | *[!0-9]* | ??????*) fail 'SQUID_MOCK_PORT は数字だけ（1から65535）' ;;
  esac
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    fail 'SQUID_MOCK_PORT は1から65535の範囲'
  fi
  NEW_PEER="cache_peer $host parent $port 0 no-query name=wiremock"
  LINE_PEER=$LINE_PEER NEW_PEER=$NEW_PEER awk '
    $0 == ENVIRON["LINE_PEER"] { print ENVIRON["NEW_PEER"]; next }
    { print }
  ' "$src" >"$dst.tmp"
else
  # direct は、WireMock への転送の行を外し、直接接続を許可する行へ置き換える。
  # Why: SQUID_MOCK_* は読まない。本番では宛先が残っていても派生に影響させないため。
  LINE_PEER=$LINE_PEER LINE_ALLOW=$LINE_ALLOW LINE_DENY=$LINE_DENY LINE_NEVER=$LINE_NEVER awk '
    $0 == ENVIRON["LINE_PEER"] { next }
    $0 == ENVIRON["LINE_ALLOW"] { next }
    $0 == ENVIRON["LINE_DENY"] { next }
    $0 == ENVIRON["LINE_NEVER"] { print "always_direct allow api_domains"; next }
    { print }
  ' "$src" >"$dst.tmp"
fi
mv "$dst.tmp" "$dst"
