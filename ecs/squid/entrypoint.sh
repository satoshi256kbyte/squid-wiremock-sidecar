#!/bin/sh
# Squid コンテナの起動（M09 FR-908、plan 3.4）。
# 派生、parse、上流の表示、元のエントリポイントへの引き渡しの順に動く。
# Why: 元のエントリポイントは起動時に squid -Nz を実行するため、派生した設定を先に置く必要がある（G5）。
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
# Why exec: 元のエントリポイントに制御を渡し、イメージの Cmd と同じ引数で squid を起動する（G5）。
exec /usr/local/bin/entrypoint.sh -f /etc/squid/squid.conf -NYC
