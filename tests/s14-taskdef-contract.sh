#!/bin/sh
# S14 の契約検査（unit）。Docker を使わず、固定の ACL 行、派生設定の構文、WireMock の読み取り専用、
# Squid のホスト非公開を確かめる。Compose の展開検査（tests/s14-compose-port-binding.sh）の代わり。
# Why: Compose の展開に依存する検査を、Docker の無い環境でも同じ判定で動かせるようにするため。
# 使い方: sh tests/s14-taskdef-contract.sh unit
set -eu

if [ $# -ne 1 ] || [ "$1" != unit ]; then
  printf 'usage: sh tests/s14-taskdef-contract.sh unit\n' >&2
  exit 2
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# 作業場所は実行ごとに作り、終了時に消す。空のときに rm を走らせないため、作成の後にだけ変数を設定する。
TMP=
cleanup() {
  if [ -n "$TMP" ]; then
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
_base=${KIROCREW_SCRATCH:-${TMPDIR:-/tmp}}
mkdir -p "$_base"
TMP=$(mktemp -d "$_base/s14-unit.XXXXXX")

# docker を呼んだら記録する偽物を、PATH の先頭に置く。
# Why: この検査が Docker に触れないことを、呼び出しの記録で確かめるため。
mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "docker $*" >>"%s"\nexit 1\n' "$TMP/docker-calls" >"$TMP/bin/docker"
chmod +x "$TMP/bin/docker"
PATH="$TMP/bin:$PATH"
export PATH

total=0
failures=0

# 検査を1件ずつ実行し、結果だけを出す。検査の関数は if の中で呼ばれるため、失敗は必ず return 1 で返す。
check() { # 名前 関数
  total=$((total + 1))
  if ("$2") >"$TMP/case.log" 2>&1; then
    printf 'ok: %s\n' "$1"
  else
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1"
    sed 's/^/    /' "$TMP/case.log" >&2
  fi
}

# 固定の ACL 行。送信元の範囲と許可・拒否の行を、完全一致で確かめる。
s14_acl_lines() {
  _c=squid-config/squid.conf
  grep -Fxq -- 'acl local_src src 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16' "$_c" || return 1
  grep -Fxq -- 'http_access allow local_src api_domains' "$_c" || return 1
  grep -Fxq -- 'http_access deny all' "$_c" || return 1
  grep -Fxq -- 'cache deny all' "$_c" || return 1
  # 送信元を見ない旧い許可行が残ると、範囲外の送信元が許可ドメインへ届くため、行の数と併せて確かめる。
  [ "$(grep -c '^http_access ' "$_c")" -eq 2 ] || return 1
  ! grep -Fxq -- 'http_access allow api_domains' "$_c"
}

# 派生設定の構文の静的検査。Squid を起動せず、派生の結果の指令名を派生元と照らす。
# Why: squid -k parse は Docker が要るため、ここでは派生の出力が既知の指令だけで書かれていることを確かめる。
s14_derived_config_parse() {
  _src=squid-config/squid.conf
  _mock=$TMP/derived-mock.conf
  _direct=$TMP/derived-direct.conf
  SQUID_UPSTREAM=mock SQUID_MOCK_HOST=swsc-wiremock SQUID_MOCK_PORT=8080 \
    sh ecs/squid/derive-config.sh "$_src" "$_mock" || return 1
  SQUID_UPSTREAM=direct sh ecs/squid/derive-config.sh "$_src" "$_direct" || return 1

  # mock は転送先の行を1つだけ持ち、派生元の転送行は残らない。
  [ "$(grep -c '^cache_peer ' "$_mock")" -eq 1 ] || return 1
  grep -Fxq -- 'cache_peer swsc-wiremock parent 8080 0 no-query name=wiremock' "$_mock" || return 1
  grep -Fxq -- 'cache_peer_access wiremock allow api_domains' "$_mock" || return 1
  # direct は転送の行が無く、直接接続の行を持つ。
  [ "$(grep -c '^cache_peer' "$_direct" || true)" -eq 0 ] || return 1
  grep -Fxq -- 'always_direct allow api_domains' "$_direct" || return 1

  # 有効な行（空行と # のコメントを除く）の先頭語を集める。派生元の指令名に、派生で足す always_direct を加えた集合だけを許す。
  _allowed=$TMP/allowed.txt
  grep -Ev '^[[:space:]]*(#|$)' "$_src" | awk '{ print $1 }' | sort -u >"$_allowed"
  printf '%s\n' always_direct >>"$_allowed"
  for _f in "$_mock" "$_direct"; do
    _names=$TMP/names.txt
    grep -Ev '^[[:space:]]*(#|$)' "$_f" | awk '{ print $1 }' | sort -u >"$_names"
    [ -z "$(grep -vxFf "$_allowed" "$_names" || true)" ] || return 1
  done

  # 不正な値は、派生の前に拒否する（設定へ別の指示を混ぜないため）。
  if SQUID_UPSTREAM=bogus sh ecs/squid/derive-config.sh "$_src" "$TMP/bad1.conf" >/dev/null 2>&1; then
    return 1
  fi
  if SQUID_UPSTREAM=mock SQUID_MOCK_HOST='a b' SQUID_MOCK_PORT=8080 \
    sh ecs/squid/derive-config.sh "$_src" "$TMP/bad2.conf" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# WireMock のシナリオは、読み取り専用（:ro）で1回だけ渡す。書き込み可能な宛先で渡すと、検査の前提が崩れるため。
s14_mapping_readonly() {
  _r=scripts/e2e-runner.sh
  [ "$(grep -c 'wiremock-scenarios' "$_r" || true)" -eq 1 ] || return 1
  [ "$(grep -c '/home/wiremock' "$_r" || true)" -eq 1 ] || return 1
  grep -Fxq -- '    -v "$SWSC_ROOT/wiremock-scenarios:/home/wiremock:ro" \' "$_r"
}

# Squid はホストへ公開しない。taskdef から作った docker run の引数に公開の指定が無く、
# ランナーのホスト公開は WireMock の 127.0.0.1:8080 だけであることを確かめる。
s14_squid_not_published() {
  _tpl=ecs/task-definition.template.json
  _taskdef=$TMP/taskdef.json
  _run=$TMP/run
  python3 -B scripts/e2e-taskdef.py render --template "$_tpl" --out "$_taskdef" \
    --client-image swsc-client:e2e --squid-image swsc-squid:e2e \
    --profile local --upstream mock --mock-host swsc-wiremock --mock-port 8080 >/dev/null 2>&1 || return 1
  mkdir -p "$_run"
  python3 -B scripts/e2e-taskdef.py docker-args --taskdef "$_taskdef" --out-dir "$_run" \
    --pause-name swsc-pause --run-id 4242 >/dev/null 2>&1 || return 1
  [ -f "$_run/swsc-squid.args" ] || return 1
  ! grep -Eq -- '^(-p|-P|--publish|--publish-all)' "$_run/swsc-squid.args" || return 1
  ! grep -Eq -- ':3128' "$_run/swsc-squid.args" || return 1
  # ランナーの公開指定は、数字で始まる -p（空白なしの -p8080:8080 も含む docker run の公開）の1件だけで、127.0.0.1 の 8080 に限る。
  # mkdir -p のような別のコマンドの -p は数えない。
  # Why: grep -c は行の数を数え、同じ行の2つ目の -p を見落とすため、一致した数を数える。
  [ "$(grep -Eo -- ' -p ?[0-9]' scripts/e2e-runner.sh | wc -l | tr -d ' ')" -eq 1 ] || return 1
  grep -Fq -- ' -p 127.0.0.1:8080:8080' scripts/e2e-runner.sh || return 1
  # -P と --publish-all は全ポートを全インターフェースへ公開するため、ランナーに置かない。
  ! grep -Eq -- ' -P( |$)|--publish|3128:|0\.0\.0\.0:' scripts/e2e-runner.sh
}

# 許可ドメインは、有効な行（空行と # のコメントを除く）が2件だけで、内容も固定する。
# Why: 行を足すと、SQUID_UPSTREAM=direct のときに、レビューを経ずに外部への通信先が広がるため（旧 S14 の検査を引き継ぐ）。
s14_allowlist_fixed() {
  _w=squid-config/whitelist.txt
  _got=$(grep -Ev '^[[:space:]]*(#|$)' "$_w" | sort)
  _want=$(printf '%s\n' api-staging.example.com api.example.com | sort)
  [ "$_got" = "$_want" ]
}

check 's14_acl_lines: 固定の ACL 行と許可・拒否の行が規定どおり' s14_acl_lines
check 's14_derived_config_parse: 派生設定の指令が既知の指令だけで、不正な値を拒否する' s14_derived_config_parse
check 's14_mapping_readonly: WireMock のシナリオが読み取り専用で渡される' s14_mapping_readonly
check 's14_squid_not_published: Squid の 3128 がホストへ公開されない' s14_squid_not_published
check 's14_allowlist_fixed: 許可ドメインが api.example.com と api-staging.example.com の2件だけ' s14_allowlist_fixed

# この検査は Docker を呼ばない。呼ばれていたら、検査の前提が崩れているため失敗にする。
if [ -e "$TMP/docker-calls" ]; then
  failures=$((failures + 1))
  printf 'FAIL: 検査が docker を呼んだ\n' >&2
fi

if [ "$failures" -ne 0 ]; then
  printf 's14 taskdef contract: %d 件中 %d 件失敗\n' "$total" "$failures" >&2
  exit 1
fi
printf 's14 taskdef contract: %d 件中 %d 件通過\n' "$total" "$total"
exit 0
