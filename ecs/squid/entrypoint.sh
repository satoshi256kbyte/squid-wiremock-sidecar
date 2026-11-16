#!/bin/sh
# Squid コンテナの起動スクリプト。次の順に動く。
#   1. derive-config.sh で、squid.conf を環境変数に合わせて書き換える
#   2. squid -k parse で、書き換えた設定の構文を確かめる
#   3. 元のエントリポイントに渡して、Squid を起動する
# 元のエントリポイントは起動時に squid -Nz を実行するため、書き換えた設定を先に置いておく必要がある。
set -eu

if ! /usr/local/bin/swsc-derive-config.sh /etc/squid/squid.conf.src /etc/squid/squid.conf; then
  printf 'swsc-squid: 設定の派生に失敗\n' >&2
  exit 1
fi
if ! squid -k parse -f /etc/squid/squid.conf; then
  printf 'swsc-squid: squid -k parse に失敗\n' >&2
  exit 1
fi
printf 'swsc-squid: upstream=%s\n' "$SQUID_UPSTREAM"
# Why exec: 元のエントリポイントに制御を渡し、イメージの Cmd と同じ引数で squid を起動する。
exec /usr/local/bin/entrypoint.sh -f /etc/squid/squid.conf -NYC
