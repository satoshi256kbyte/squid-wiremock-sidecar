#!/bin/sh
# S14 の契約検査（unit）の入口。検査の中身は tests/bats/s14-taskdef-contract.bats にある。
# Docker を使わず、固定の ACL 行、派生設定の構文、WireMock の読み取り専用、Squid のホスト非公開を確かめる。
# 使い方: sh tests/s14-taskdef-contract.sh unit
set -eu

if [ $# -ne 1 ] || [ "$1" != unit ]; then
  printf 'usage: sh tests/s14-taskdef-contract.sh unit\n' >&2
  exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
exec sh "$ROOT/tests/lib/run-bats.sh" "$ROOT/tests/bats/s14-taskdef-contract.bats" unit
